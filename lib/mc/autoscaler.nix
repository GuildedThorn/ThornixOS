# RCON-driven lobby autoscaler. Reads the player count from every Running lobby
# pod and scales the Deployment to ceil(total / max-per-lobby), bounded below by
# one and above by --max-lobbies. Arguments are supplied by the systemd unit.
{ pkgs }:
pkgs.writeScript "mc-lobby-autoscaler.py" ''
  import argparse
  import json
  import re
  import socket
  import struct
  import subprocess
  import sys
  import time


  def rcon(host, port, password, cmd, timeout=3):
      def pack(rid, ptype, body):
          data = struct.pack("<iii", rid, ptype, len(body.encode()) + 1) + body.encode("utf-8") + b"\0\0"
          return struct.pack("<i", len(data)) + data

      def recv(sock):
          (n,) = struct.unpack("<i", sock.recv(4))
          data = b""
          while len(data) < n:
              data += sock.recv(n - len(data))
          return data

      with socket.create_connection((host, port), timeout=timeout) as s:
          s.sendall(pack(1, 3, password))
          recv(s)
          s.sendall(pack(2, 2, cmd))
          body = recv(s)[12:].decode("utf-8", errors="replace").rstrip("\0")
          return body


  def kubectl(*args):
      return subprocess.run(
          ["kubectl"] + list(args), check=True, capture_output=True, text=True
      ).stdout


  def players_on(host, port, password):
      try:
          out = rcon(host, port, password, "list")
          m = re.search(r"There are (\d+) of a max of", out)
          return int(m.group(1)) if m else 0
      except Exception:
          return -1  # unreachable / not yet up


  def main():
      ap = argparse.ArgumentParser()
      ap.add_argument("--interval", type=int, default=30)
      ap.add_argument("--label", required=True)
      ap.add_argument("--deployment", required=True)
      ap.add_argument("--namespace", default="mc")
      ap.add_argument("--max-per-lobby", type=int, default=40)
      ap.add_argument("--max-lobbies", type=int, default=4)
      ap.add_argument("--rcon-port", type=int, default=25575)
      ap.add_argument("--rcon-password-file", required=True)
      args = ap.parse_args()

      with open(args.rcon_password_file) as fh:
          password = fh.read().strip()

      while True:
          try:
              pods = json.loads(
                  kubectl(
                      "get", "pods", "-n", args.namespace, "-l", args.label, "-o", "json"
                  )
              )
              items = [
                  p
                  for p in pods["items"]
                  if not p["metadata"].get("deletionTimestamp")
                  and p["status"].get("phase") == "Running"
              ]
              ips = [p["status"].get("podIP") for p in items]
              total = 0
              live = 0
              for ip in ips:
                  if not ip:
                      continue
                  count = players_on(ip, args.rcon_port, password)
                  if count >= 0:
                      live += 1
                      total += count
              desired = max(1, min(args.max_lobbies, -(-total // args.max_per_lobby)))
              if live and desired != len(ips):
                  kubectl(
                      "scale", "deployment/" + args.deployment,
                      "--replicas", str(desired),
                      "-n", args.namespace,
                  )
          except Exception as e:
              print(f"autoscaler error: {e}", file=sys.stderr)
          time.sleep(args.interval)


  if __name__ == "__main__":
      main()
''
