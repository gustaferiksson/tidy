import json
import re
import sys
from pathlib import Path

NAMES = [
    "git-pull-request", "git-pull-request-draft", "git-pull-request-closed", "git-merge",
    "issue-opened", "issue-closed", "skip", "comment-discussion", "discussion-closed",
    "tag", "git-commit", "x-circle", "check-circle", "stop", "bell",
    "alert", "key", "shield", "shield-check", "person-add",
    "check", "file-diff", "comment", "dot-fill",
]
SCALE = 79 / 16
SIDE_BEARING = 7.0
CAP_CENTRE = 70.459 / 2
WEIGHT_COLUMNS = {"Ultralight-S": 559.711, "Regular-S": 1449.84, "Black-S": 2933.4}
BASELINE_S = 696

NUMBER = re.compile(r"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?")
ARITY = {"m": 2, "l": 2, "h": 1, "v": 1, "c": 6, "s": 4, "q": 4, "t": 2, "a": 7, "z": 0}


def tokens(d):
    i = 0
    out = []
    command = None
    numbers_since_command = 0
    while i < len(d):
        if d[i] in " ,\t\n":
            i += 1
        elif d[i].isalpha():
            command = d[i]
            out.append(command)
            numbers_since_command = 0
            i += 1
        elif command in "aA" and numbers_since_command % 7 in (3, 4):
            out.append(float(d[i]))
            numbers_since_command += 1
            i += 1
        else:
            match = NUMBER.match(d, i)
            if not match:
                raise ValueError(f"bad path data at {i}: {d[i:i + 20]}")
            out.append(float(match.group()))
            numbers_since_command += 1
            i = match.end()
    if out[0] == "m":
        out[0] = "M"
        if len(out) > 3 and not isinstance(out[3], str):
            out.insert(3, "l")
    return out


def fmt(value):
    text = f"{value:.4f}".rstrip("0").rstrip(".")
    return "0" if text in ("-0", "") else text


def transform(d, dx, dy):
    out = []
    items = tokens(d)
    i = 0
    while i < len(items):
        command = items[i]
        i += 1
        out.append(command)
        arity = ARITY[command.lower()]
        if arity == 0:
            continue
        absolute = command.isupper()
        while i < len(items) and not isinstance(items[i], str):
            args = items[i:i + arity]
            i += arity
            lower = command.lower()
            if lower == "h":
                values = [args[0] * SCALE + (dx if absolute else 0)]
            elif lower == "v":
                values = [args[0] * SCALE + (dy if absolute else 0)]
            elif lower == "a":
                rx, ry, rotation, large, sweep, x, y = args
                values = [rx * SCALE, ry * SCALE, rotation, large, sweep,
                          x * SCALE + (dx if absolute else 0), y * SCALE + (dy if absolute else 0)]
            else:
                values = [v * SCALE + ((dx if k % 2 == 0 else dy) if absolute else 0) for k, v in enumerate(args)]
            out.append(" ".join(fmt(v) for v in values))
    return " ".join(out)


def symbol_svg(name, paths):
    width = 16 * SCALE + 2 * SIDE_BEARING
    dy = -CAP_CENTRE - 8 * SCALE
    glyph = "\n".join(f'   <path d="{transform(d, SIDE_BEARING, dy)}"/>' for d in paths)
    margins = []
    groups = []
    for weight, centre in WEIGHT_COLUMNS.items():
        left = centre - width / 2
        right = left + width
        margins.append(f'  <line id="left-margin-{weight}" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" x1="{fmt(left)}" x2="{fmt(left)}" y1="600.785" y2="720.121"/>')
        margins.append(f'  <line id="right-margin-{weight}" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" x1="{fmt(right)}" x2="{fmt(right)}" y1="600.785" y2="720.121"/>')
        groups.append(f'  <g id="{weight}" transform="matrix(1 0 0 1 {fmt(left)} {BASELINE_S})">\n{glyph}\n  </g>')
    guides = []
    for scale, baseline in (("S", 696), ("M", 1126), ("L", 1556)):
        guides.append(f'  <line id="Baseline-{scale}" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="{baseline}" y2="{baseline}"/>')
        guides.append(f'  <line id="Capline-{scale}" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="{fmt(baseline - 70.459)}" y2="{fmt(baseline - 70.459)}"/>')
    newline = "\n"
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<svg version="1.1" xmlns="http://www.w3.org/2000/svg" width="3300" height="2200">
 <g id="Notes">
  <rect height="2200" id="artboard" style="fill:white;opacity:1" width="3300" x="0" y="0"/>
  <text id="template-version" style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:end;" transform="matrix(1 0 0 1 3036 1933)">Template v.4.0</text>
  <text id="descriptive-name" style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:end;" transform="matrix(1 0 0 1 3036 1969)">Octicon {name} (MIT, GitHub Inc.)</text>
 </g>
 <g id="Guides">
{newline.join(guides)}
{newline.join(margins)}
 </g>
 <g id="Symbols">
{newline.join(groups)}
 </g>
</svg>
"""


def main():
    source, catalog = Path(sys.argv[1]), Path(sys.argv[2])
    for name in NAMES:
        svg = (source / f"{name}-16.svg").read_text()
        paths = re.findall(r'<path[^>]*\sd="([^"]+)"', svg)
        if "transform" in svg or "fill-rule" in svg:
            raise SystemExit(f"{name}: unsupported attributes")
        folder = catalog / f"{name}.symbolset"
        folder.mkdir(parents=True, exist_ok=True)
        (folder / f"{name}.svg").write_text(symbol_svg(name, paths))
        contents = {"info": {"author": "xcode", "version": 1}, "symbols": [{"filename": f"{name}.svg", "idiom": "universal"}]}
        (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


main()
