{ config, pkgs, ... }:
let
  dataDir = "/platter/services/reference/rfc";

  indexHtml = pkgs.writeText "offline-rfc-index.html" ''
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Offline RFC Library</title>
      <style>
        body { font: 15px/1.5 system-ui, sans-serif; margin: 0; color: #222; background: #faf9f7; }
        header { background: #1f2933; color: #fff; padding: 14px 20px; position: sticky; top: 0; }
        header h1 { margin: 0 0 8px; font-size: 18px; }
        header small { font-weight: normal; color: #b8c2cc; }
        input { width: min(640px, 100%); padding: 8px 10px; font-size: 15px; border-radius: 4px; border: 1px solid #888; }
        main { padding: 16px 20px 40px; max-width: 1040px; margin: auto; }
        ul { list-style: none; padding: 0; }
        li { padding: 6px 0; border-bottom: 1px solid #e5e1d8; }
        a { color: #145a86; text-decoration: none; }
        a:hover { text-decoration: underline; }
        .num { display: inline-block; min-width: 68px; color: #666; font-variant-numeric: tabular-nums; }
        .status { color: #777; font-size: 12px; margin-left: 8px; }
        pre { white-space: pre-wrap; word-break: break-word; background: #fff; padding: 16px; border: 1px solid #ddd; border-radius: 4px; }
        .meta { color: #666; margin-bottom: 12px; }
      </style>
    </head>
    <body>
      <header>
        <h1>Offline RFC Library <small id="count"></small></h1>
        <input id="q" placeholder="Search RFC number, title, status…" autofocus>
      </header>
      <main id="main">Loading index…</main>
      <script>
        var entries = [];

        function parse(text) {
          var out = [];
          var blocks = text.split(/\n\s*\n/);
          for (var i = 0; i < blocks.length; i++) {
            var b = blocks[i].replace(/\s+/g, " ").trim();
            var m = b.match(/^(\d{1,5})\s+(.+)$/);
            if (!m || /^Not Issued\./.test(m[2])) continue;
            var status = (m[2].match(/\(Status:\s*([^)]+)\)/) || [null, ""])[1];
            var title = m[2].split(/\.\s/)[0];
            out.push({ n: m[1], title: title, text: m[2], status: status });
          }
          return out;
        }

        function esc(s) {
          return String(s).replace(/[&<>"]/g, function (c) {
            return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
          });
        }

        function renderList(filter) {
          var q = filter.toLowerCase();
          var html = "<ul>";
          var shown = 0;
          for (var i = 0; i < entries.length; i++) {
            var e = entries[i];
            if (q && e.text.toLowerCase().indexOf(q) < 0) continue;
            html += '<li><span class="num">RFC ' + e.n + '</span><a href="#/rfc/' + e.n + '">' + esc(e.title) + '</a>';
            if (e.status) html += '<span class="status">' + esc(e.status) + '</span>';
            html += "</li>";
            if (++shown >= 500) break;
          }
          html += "</ul>";
          if (shown >= 500) html += "<p>Showing the first 500 matches — narrow your search.</p>";
          document.getElementById("main").innerHTML = html;
        }

        function renderRfc(n) {
          var main = document.getElementById("main");
          main.innerHTML = '<p class="meta"><a href="#/">&larr; Back to index</a> &middot; RFC ' + esc(n) +
            ' &middot; <a href="rfc' + esc(n) + '.txt" target="_blank">Open raw text</a></p><pre id="doc">Loading…</pre>';
          fetch("rfc" + esc(n) + ".txt").then(function (r) { return r.text(); }).then(function (t) {
            document.getElementById("doc").textContent = t;
          }).catch(function (e) {
            document.getElementById("doc").textContent = "Failed to load: " + e;
          });
        }

        function route() {
          var m = location.hash.match(/^#\/rfc\/(\d+)$/);
          if (m) renderRfc(m[1]);
          else renderList(document.getElementById("q").value);
        }

        document.getElementById("q").addEventListener("input", function () {
          if (!location.hash || location.hash === "#/") renderList(this.value);
        });
        window.addEventListener("hashchange", route);

        fetch("rfc-index.txt").then(function (r) { return r.text(); }).then(function (t) {
          entries = parse(t);
          document.getElementById("count").textContent = "(" + entries.length + " RFCs)";
          route();
        }).catch(function (e) {
          document.getElementById("main").textContent = "Failed to load rfc-index.txt: " + e;
        });
      </script>
    </body>
    </html>
  '';
in
{
  assertions = [
    {
      assertion = config.networking.hostName == "granite";
      message = "the offline RFC viewer is currently intended for the granite host";
    }
  ];

  # The RFC mirror stays a manual rsync under /platter. Symlink the viewer
  # into it so the existing /rfc/ nginx alias serves both with no new service.
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0755 root root -"
    "L+ ${dataDir}/index.html - - - - ${indexHtml}"
  ];
}
