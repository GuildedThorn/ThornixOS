# MITM / Home Assistant / Voice HAT / RS11 handoff

## Worktree safety
- Repo dirty with many unrelated user changes. Never revert them.
- This session's main files: `modules/computers/mitm.nix`, `hosts/mitm/{hardware-configuration.nix,networking.nix,admin-ssh-keys.nix,disko.nix,thorn-home.yaml}`, `modules/computers/voice-office.nix`, `hosts/voice-office/{admin-ssh-keys.nix,googlevoicehat-soundcard-overlay.dts}`, `hosts/inventory.nix`, `flake.nix`, `flake.lock`, `README.md`.
- No commits created.

## MITM live state
- Host: `mitm`, `172.16.25.2`, NixOS installed via nix-anywhere onto WD PC SN730 256 GB NVMe.
- Root SSH is key-only; use `/home/thorn/.ssh/id_ed25519`. Never persist installer password.
- Home Assistant: `https://mitm.guildedthorn.arpa`; ThornCloud ACME + nginx healthy. HA backend loopback `127.0.0.1:8123`; direct 8123 filtered.
- Dashboard: `https://mitm.guildedthorn.arpa/thorn-home/home`, source `hosts/mitm/thorn-home.yaml`.
- Existing Jellyfin is ThornFlix at `https://jellyfin.guildedthorn.com/`; MITM Jellyfin server was removed. HA `jellyfin` component enabled and user added integration.
- BLE works. Govee H6001 seen but unsupported by official HA integrations.
- Local Wyoming engines active and LAN-filtered:
  - Piper `127.0.0.1:10200`, voice `en_US-lessac-medium`
  - faster-whisper `127.0.0.1:10300`, `base-int8`, CPU
  - openWakeWord `127.0.0.1:10400`
- MITM has `boot.binfmt.emulatedSystems = [ "aarch64-linux" ]`; useful ARM builder.

## Voice satellite live state
- Hostname `voice-office`, IP `172.16.25.27`, Raspberry Pi 3B+, Google AIY Voice HAT v1.
- SSH key-only root. Temporary local known-host file was `/tmp/opencode/voice-office_known_hosts` (lost after reboot; accept/verify host key again).
- NixOS host config: `modules/computers/voice-office.nix`; inventory host uses `aarch64-linux`, deploy=false.
- Stable cached Pi kernel pinned through `nixpkgs-rpi` input (`nixos-25.11`, kernel 6.12.47). Current unstable Pi kernel source build under QEMU was cancelled as impractical.
- Voice HAT overlay needed custom compatibility for Pi 3B+ and stable-kernel node naming; source is `hosts/voice-office/googlevoicehat-soundcard-overlay.dts`.
- Current generation deployed remotely and rebooted successfully.
- ALSA card registered as `sndrpigooglevoi`, playback and capture device 0.
- 2-second microphone capture succeeded (64,044-byte WAV); 880 Hz speaker tone wrote successfully.
- `wyoming-satellite.service` active; no failed units.
- Satellite endpoint `172.16.25.27:10700`; firewall permits source `172.16.25.2` only. MITM connectivity test passed.
- Home Assistant still needs Wyoming config entries if not already added:
  - `127.0.0.1:10200` Piper
  - `127.0.0.1:10300` Whisper
  - `127.0.0.1:10400` openWakeWord
  - `172.16.25.27:10700` Office Voice satellite
  Then create/select Assist pipeline.

## Recovery image
- Corrected final image exists locally at volatile `/tmp/opencode/voice-office.img.zst` and on MITM via `/var/lib/voice-office-final-image/sd-image/`.
- Corrected image SHA-256: `14e981470679555d494432a962dc783b47b133144c39070c0bb410ea3be44e29`.
- Compressed 1.7 GB; raw 6,238,547,968 bytes; zstd integrity passed.
- If local machine reboots, `/tmp` copy disappears; authoritative MITM copy remains persistent.

## Buffbee RS11 investigation
- Donor device: Buffbee RS11 alarm clock/speaker, board marking `RS11-MAIN version 15`.
- Header labels: RX, TX, VDD/VCC, GND.
- Fresh multimeter readings on DC 20 V: VCC-to-GND `3.32 V`; TX and RX steady `0 V`.
- This indicates 3.3 V logic supply, but UART idling low is unusual. Could activate only at boot/button press, labels may be opposite-board perspective, protocol may be inverted/non-UART, or daughterboard required.
- Do not connect VCC between RS11 and Arduino/Pi.
- Safe receive-only sniff wiring: RS11 GND -> Arduino GND; RS11 TX -> Arduino receive pin; leave RS11 VCC, RS11 RX, and Arduino TX disconnected.
- Need Arduino exact model before supplying sketch/pins. Capture RS11 boot and each button press; ideally monitor both TX/RX with 2-channel logic analyzer.
- RS11 speaker must connect to only one amplifier at a time; never tie RS11 amp and Voice HAT amp outputs together.
- Earlier front-button harness was identified as Black=GND, Red=LED, White=Key, but UART mainboard path is now preferred for reverse engineering.

## Immediate next step
1. Ask Arduino model or obtain logic-analyzer capture.
2. Configure four Wyoming integrations/pipeline in HA if pending.
3. Optionally add Voice HAT GPIO button/LED behavior after pipeline works.
