#!/usr/bin/env python3
"""Extract ThornixOS `thorn.*` option declarations from Nix module sources.

This intentionally parses source rather than evaluating the full NixOS module
set: several upstream modules in this flake are not doc-evaluation safe, while
the declarations themselves are stable and easy to read mechanically.
"""

from __future__ import annotations

import html
import json
import os
import re
import sys

DECL_RE = re.compile(
    r"\boptions\.thorn\.([A-Za-z_][A-Za-z0-9_-]*(?:\.[A-Za-z_][A-Za-z0-9_-]*)*)"
)
ASSIGN_RE = re.compile(r"\b([A-Za-z_][A-Za-z0-9_-]*)\s*=")
DESC_RE = re.compile(
    r"\bdescription\s*=\s*(?:''(.+?)''|\"((?:\\.|[^\"\\])*)\"|([A-Za-z_][A-Za-z0-9_.]*))",
    re.S,
)
TYPE_RE = re.compile(r"\btype\s*=\s*([^;\n]+);")
ENABLE_RE = re.compile(
    r"\bmkEnableOption\s*(?:\(\s*)?(?:''(.+?)''|\"((?:\\.|[^\"\\])*)\")",
    re.S,
)
PACKAGE_RE = re.compile(
    r"\bmkPackageOption\s+[A-Za-z0-9_.]+\s+(?:''(.+?)''|\"([^\"]+)\")",
    re.S,
)


def unquote(value: str) -> str:
    """Normalise a Nix string literal fragment into plain text."""
    value = value.replace('\\"', '"').replace("\\\\", "\\")
    lines = [line.rstrip() for line in value.strip().splitlines()]
    nonempty = [line for line in lines if line.strip()]
    indent = min((len(line) - len(line.lstrip()) for line in nonempty), default=0)
    lines = [line[indent:] if line.strip() else "" for line in lines]
    return re.sub(r"\s+", " ", "\n".join(lines)).strip()


def skip_string(text: str, index: int) -> int:
    """Return the index just after the string starting at `index`."""
    if text.startswith("''", index):
        index += 2
        while index < len(text):
            if text.startswith("'''", index):
                index += 3
            elif text.startswith("''", index):
                return index + 2
            else:
                index += 1
        return len(text)
    if text[index] == '"':
        index += 1
        while index < len(text):
            if text[index] == "\\":
                index += 2
            elif text[index] == '"':
                return index + 1
            else:
                index += 1
        return len(text)
    return index + 1


def skip_comment(text: str, index: int) -> int:
    """Return the index just after the comment starting at `index`."""
    if text.startswith("#", index):
        newline = text.find("\n", index)
        return len(text) if newline < 0 else newline + 1
    if text.startswith("/*", index):
        close = text.find("*/", index + 2)
        return len(text) if close < 0 else close + 2
    return index + 1


def matching_brace(text: str, start: int) -> int:
    """Find the closing brace for the `{` at `start`."""
    depth = 0
    index = start
    while index < len(text):
        char = text[index]
        if char in {'"', "'"}:
            index = skip_string(text, index)
            continue
        if char == "#" or text.startswith("/*", index):
            index = skip_comment(text, index)
            continue
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return index
        index += 1
    return len(text)


def top_level_assignments(body: str) -> list[tuple[str, int]]:
    """Yield (attribute name, value offset) for direct assignments in a set."""
    result: list[tuple[str, int]] = []
    index = 0
    depth = 0
    while index < len(body):
        char = body[index]
        if char in {'"', "'"}:
            index = skip_string(body, index)
            continue
        if char == "#" or body.startswith("/*", index):
            index = skip_comment(body, index)
            continue
        if char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
        elif depth == 0:
            match = ASSIGN_RE.match(body, index)
            if match:
                value = match.end()
                while value < len(body) and body[value].isspace():
                    value += 1
                result.append((match.group(1), value))
                index = match.end()
                continue
        index += 1
    return result


def constructor_at(text: str, value_start: int) -> str:
    """Name the option constructor used at `value_start`, if any."""
    matched = re.match(
        r"\s*(?:lib\.)?(mkOption|mkEnableOption|mkPackageOption)\b",
        text[value_start : value_start + 80],
    )
    return matched.group(1) if matched else ""


def option_body(text: str, value_start: int) -> tuple[int, int] | None:
    """Return the bounds of the `{ ... }` argument to `mkOption`."""
    if constructor_at(text, value_start) != "mkOption":
        return None
    brace = text.find("{", value_start)
    if brace < 0:
        return None
    end = matching_brace(text, brace)
    return brace + 1, end


def describe_option(text: str, value_start: int, body: tuple[int, int] | None) -> tuple[str, str]:
    """Return (description, type) for an option constructor expression."""
    if body is None:
        window = text[value_start : value_start + 600]
        enable = ENABLE_RE.search(window)
        if enable:
            return unquote(next((group for group in enable.groups() if group), "") or ""), "boolean"
        package = PACKAGE_RE.search(window)
        if package:
            package_name = next((group for group in package.groups() if group), "")
            return f"Package for {package_name}.", "package"
        return "", ""

    segment = text[body[0] : body[1]]
    matched = DESC_RE.search(segment)
    description = unquote(next((group for group in matched.groups() if group), "")) if matched else ""
    type_matched = TYPE_RE.search(segment)
    option_type = re.sub(r"\s+", " ", type_matched.group(1)).strip() if type_matched else ""
    return description, option_type


def add_leaf(options: dict[str, dict], name: str, text: str, value_start: int, declaration: str, line: int) -> None:
    body = option_body(text, value_start)
    description, option_type = describe_option(text, value_start, body)
    options[name] = {
        "name": name,
        "description": description,
        "type": option_type,
        "declaration": declaration,
        "line": line,
    }


def parse_value(
    options: dict[str, dict],
    prefix: str,
    text: str,
    value_start: int,
    declaration: str,
    line: int,
) -> None:
    """Parse an option declaration, recursing through nested option sets."""
    value = text[value_start : value_start + 80]
    constructor = re.match(r"\s*(?:lib\.)?(mkOption|mkEnableOption|mkPackageOption)\b", value)
    if constructor:
        add_leaf(options, prefix, text, value_start, declaration, line)
        return

    if text[value_start : value_start + 1] == "{":
        end = matching_brace(text, value_start)
        body = text[value_start + 1 : end]
        for key, nested in top_level_assignments(body):
            parse_value(
                options,
                f"{prefix}.{key}",
                body,
                nested,
                declaration,
                line,
            )


def extract(root: str) -> list[dict]:
    options: dict[str, dict] = {}
    for base, _dirs, files in os.walk(root):
        for filename in sorted(files):
            if not filename.endswith(".nix"):
                continue
            path = os.path.join(base, filename)
            relative = os.path.relpath(path, root)
            if relative == "core/thorn-options-doc.nix":
                continue
            with open(path, encoding="utf-8") as handle:
                text = handle.read()

            for match in DECL_RE.finditer(text):
                name = f"thorn.{match.group(1)}"
                equals = text.find("=", match.end())
                if equals < 0:
                    continue
                value_start = equals + 1
                while value_start < len(text) and text[value_start].isspace():
                    value_start += 1
                line = text.count("\n", 0, match.start()) + 1
                parse_value(options, name, text, value_start, relative, line)

    return [options[key] for key in sorted(options)]


def render_json(options: list[dict]) -> str:
    return json.dumps({"source": "modules/**/*.nix", "options": options}, indent=2) + "\n"


def render_html(options: list[dict]) -> str:
    rows = "\n".join(
        "<tr>"
        f"<td><code>{html.escape(item['name'])}</code></td>"
        f"<td>{html.escape(item['type']) or '—'}</td>"
        f"<td>{html.escape(item['description']) or '—'}</td>"
        f"<td><code>{html.escape(item['declaration'])}:{item['line']}</code></td>"
        "</tr>"
        for item in options
    )
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>ThornixOS thorn.* options</title>
  <style>
    body {{ font: 15px/1.5 system-ui, sans-serif; margin: 2rem auto; max-width: 90rem; padding: 0 1rem; }}
    table {{ border-collapse: collapse; width: 100%; }}
    th, td {{ border-bottom: 1px solid #ddd; padding: .45rem .6rem; text-align: left; vertical-align: top; }}
    th {{ background: #f5f5f5; position: sticky; top: 0; }}
    input {{ font: inherit; margin-bottom: 1rem; padding: .4rem .6rem; width: 30rem; max-width: 100%; }}
    a {{ color: #0645ad; }}
    code {{ white-space: nowrap; }}
  </style>
</head>
<body>
  <h1>ThornixOS <code>thorn.*</code> options</h1>
  <p>{len(options)} options extracted from this flake's module sources.
     Machine-readable copy: <a href="/thorn-options.json">/thorn-options.json</a>.</p>
  <input id="filter" type="search" placeholder="Filter options" aria-label="Filter options">
  <table>
    <thead><tr><th>Option</th><th>Type</th><th>Description</th><th>Declared in</th></tr></thead>
    <tbody id="rows">{rows}</tbody>
  </table>
  <script>
    const filter = document.getElementById('filter');
    filter.addEventListener('input', () => {{
      const needle = filter.value.toLowerCase();
      document.querySelectorAll('#rows tr').forEach(row => {{
        row.hidden = !row.textContent.toLowerCase().includes(needle);
      }});
    }});
  </script>
</body>
</html>
"""


def main() -> None:
    root = sys.argv[1]
    mode = sys.argv[2] if len(sys.argv) > 2 else "json"
    options = extract(root)
    if mode == "html":
        sys.stdout.write(render_html(options))
    else:
        sys.stdout.write(render_json(options))


if __name__ == "__main__":
    main()
