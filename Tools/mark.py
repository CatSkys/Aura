#!/usr/bin/env python3
"""The mark, as Swift.

The logo is drawn in the app as a vector — a path read at the size the view
asks for, never a picture scaled up — and a path is the one thing Swift has
to be told at compile time. This turns the SVG the designer exports into a
`Sources/Aura/AuraMark.swift` the shapes read:

    ./Tools/mark.py Icon/mark.svg

What comes out is absolute M, L, C and Z in the SVG's own viewBox, with the
path's transform worked into the numbers and every arc turned into cubics —
the commands Path understands. Flat shapes only: what Figma and Illustrator
write when a logo is exported as one path, which is all the mark needs.
"""

import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


# —— the path data ————————————————————————————————————————————————

TOKEN = re.compile(r"[MmLlHhVvCcSsQqTtAaZz]|-?\d*\.?\d+(?:[eE][-+]?\d+)?")


def numbers(tokens, start, count):
    out = []
    i = start
    while len(out) < count:
        out.append(float(tokens[i]))
        i += 1
    return out, i


def arc_to_cubics(x1, y1, rx, ry, phi_deg, large, sweep, x2, y2):
    """One SVG arc as cubics — SVG's own implementation notes (F.6.5, F.6.6)."""
    if (x1, y1) == (x2, y2):
        return []
    rx, ry = abs(rx), abs(ry)
    if rx == 0 or ry == 0:
        return [("L", [x2, y2])]
    phi = math.radians(phi_deg % 360)
    cos, sin = math.cos(phi), math.sin(phi)
    dx, dy = (x1 - x2) / 2, (y1 - y2) / 2
    x1p = cos * dx + sin * dy
    y1p = -sin * dx + cos * dy
    lam = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
    if lam > 1:
        rx, ry = rx * math.sqrt(lam), ry * math.sqrt(lam)
    sign = -1 if large == sweep else 1
    num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
    den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
    coef = sign * math.sqrt(max(0.0, num / den)) if den else 0.0
    cxp = coef * rx * y1p / ry
    cyp = -coef * ry * x1p / rx
    cx = cos * cxp - sin * cyp + (x1 + x2) / 2
    cy = sin * cxp + cos * cyp + (y1 + y2) / 2

    def angle(ux, uy, vx, vy):
        dot = ux * vx + uy * vy
        norm = math.hypot(ux, uy) * math.hypot(vx, vy)
        a = math.acos(max(-1.0, min(1.0, dot / norm))) if norm else 0.0
        return -a if ux * vy - uy * vx < 0 else a

    theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    dtheta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
    if not sweep and dtheta > 0:
        dtheta -= 2 * math.pi
    elif sweep and dtheta < 0:
        dtheta += 2 * math.pi

    # A quarter turn a cubic: the most one can be without visibly leaving the arc.
    pieces = max(1, int(math.ceil(abs(dtheta) / (math.pi / 2))))
    step = dtheta / pieces
    alpha = 4 / 3 * math.tan(step / 4)
    out = []
    for k in range(pieces):
        t1 = theta1 + k * step
        t2 = t1 + step

        def point(t):
            return (cx + rx * math.cos(t) * cos - ry * math.sin(t) * sin,
                    cy + rx * math.cos(t) * sin + ry * math.sin(t) * cos)

        def slope(t):
            return (-rx * math.sin(t) * cos - ry * math.cos(t) * sin,
                    -rx * math.sin(t) * sin + ry * math.cos(t) * cos)

        p1, p2 = point(t1), point(t2)
        d1, d2 = slope(t1), slope(t2)
        out.append(("C", [p1[0] + alpha * d1[0], p1[1] + alpha * d1[1],
                          p2[0] - alpha * d2[0], p2[1] - alpha * d2[1],
                          p2[0], p2[1]]))
    return out


def parse(d):
    """The path as absolute M, L, C, Z — every other command said in those."""
    tokens = TOKEN.findall(d)
    out = []
    i, cmd = 0, None
    x = y = 0.0
    start = (0.0, 0.0)
    while i < len(tokens):
        if TOKEN.fullmatch(tokens[i]) and tokens[i].isalpha():
            cmd = tokens[i]
            i += 1
            if cmd in "Zz":
                out.append(("Z", []))
                x, y = start
                continue
        rel = cmd.islower()
        c = cmd.upper()
        if c == "M":
            (nx, ny), i = numbers(tokens, i, 2)
            x, y = (x + nx, y + ny) if rel else (nx, ny)
            start = (x, y)
            out.append(("M", [x, y]))
            cmd = "l" if rel else "L"      # further pairs are lines
        elif c == "L":
            (nx, ny), i = numbers(tokens, i, 2)
            x, y = (x + nx, y + ny) if rel else (nx, ny)
            out.append(("L", [x, y]))
        elif c == "H":
            (nx,), i = numbers(tokens, i, 1)
            x = x + nx if rel else nx
            out.append(("L", [x, y]))
        elif c == "V":
            (ny,), i = numbers(tokens, i, 1)
            y = y + ny if rel else ny
            out.append(("L", [x, y]))
        elif c == "C":
            n, i = numbers(tokens, i, 6)
            if rel:
                n = [n[0] + x, n[1] + y, n[2] + x, n[3] + y, n[4] + x, n[5] + y]
            out.append(("C", n))
            x, y = n[4], n[5]
        elif c == "A":
            n, i = numbers(tokens, i, 7)
            ex, ey = (x + n[5], y + n[6]) if rel else (n[5], n[6])
            out.extend(arc_to_cubics(x, y, n[0], n[1], n[2], n[3], n[4], ex, ey))
            x, y = ex, ey
        else:
            raise SystemExit(f"{cmd} isn't a command this reader knows")
    return out


# —— the file ————————————————————————————————————————————————————

def transforms(text):
    """translate(x,y) and scale(s) in a transform attribute, in order."""
    found = re.search(r'transform="([^"]*)"', text)
    matrix = (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)   # a b c d e f
    if not found:
        return matrix
    for name, args in re.findall(r"(translate|scale|matrix)\s*\(([^)]*)\)", found.group(1)):
        v = [float(t) for t in re.split(r"[,\s]+", args.strip()) if t]
        if name == "translate":
            m = (1.0, 0.0, 0.0, 1.0, v[0], v[1] if len(v) > 1 else 0.0)
        elif name == "scale":
            s = v[0]
            m = (s, 0.0, 0.0, v[1] if len(v) > 1 else s, 0.0, 0.0)
        else:
            m = tuple(v)
        # Apply the new one before what came before it: rightmost first in SVG.
        matrix = compose(m, matrix)
    return matrix


def compose(m, n):
    """m then n — the SVG order, where the rightmost transform is applied first."""
    a1, b1, c1, d1, e1, f1 = m
    a2, b2, c2, d2, e2, f2 = n
    return (a1 * a2 + b1 * c2, a1 * b2 + b1 * d2,
            c1 * a2 + d1 * c2, c1 * b2 + d1 * d2,
            e1 * a2 + f1 * c2 + e2, e1 * b2 + f1 * d2 + f2)


def apply(matrix, x, y):
    a, b, c, d, e, f = matrix
    return a * x + c * y + e, b * x + d * y + f


def main(argv):
    source = Path(argv[1]) if len(argv) > 1 else ROOT / "Icon" / "mark.svg"
    text = source.read_text(encoding="utf-8")
    box = re.search(r'viewBox="([^"]*)"', text)
    if not box:
        raise SystemExit("the SVG needs a viewBox")
    vx, vy, vw, vh = [float(t) for t in re.split(r"[,\s]+", box.group(1).strip())]
    path = re.search(r'<path[^>]*\sd="([^"]*)"', text)
    if not path:
        raise SystemExit("the SVG needs one path")

    matrix = transforms(text)
    commands = []
    for c, n in parse(path.group(1)):
        if c == "M":
            x, y = apply(matrix, n[0], n[1])
            commands.append(f"M{round(x, 2):g} {round(y, 2):g}")
        elif c == "L":
            x, y = apply(matrix, n[0], n[1])
            commands.append(f"L{round(x, 2):g} {round(y, 2):g}")
        elif c == "C":
            points = [apply(matrix, n[k], n[k + 1]) for k in (0, 2, 4)]
            commands.append("C" + " ".join(f"{round(px, 2):g} {round(py, 2):g}" for px, py in points))
        else:
            commands.append("Z")

    data = "".join(commands)
    out = ROOT / "Sources" / "Aura" / "AuraMark.swift"
    out.write_text(f'''import CoreGraphics

// The mark. Written by ./Tools/mark.py from {source.name} — read in the app as a
// path at whatever size it is drawn, so it stays a crisp vector at every one.
// Edit the SVG and run the tool again; this file is not one to write by hand.

enum AuraMark {{
    /// The SVG's own viewBox, in its own units.
    static let canvas = CGSize(width: {round(vw, 2):g}, height: {round(vh, 2):g})

    /// Absolute M, L, C, Z: the path with its transform worked in and its
    /// arcs turned into cubics.
    static let data = "{data}"
}}
''', encoding="utf-8")
    print(f"{out.relative_to(ROOT)}: {len(commands)} commands, canvas {vw:g}×{vh:g}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
