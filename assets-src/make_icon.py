"""Writes TurboMon's icon SVGs: a turbo gauge whose needle sits in the red
zone, with a live-usage line under the hub. Run, then render with render.js."""
import math

CX, CY, R, W = 512, 540, 250, 56
SEGMENTS = [(135, 236, "#4CAF50"), (240, 306, "#FFC107"), (310, 356, "#FF8C1A"), (360, 405, "#F44336")]

def pt(a, r=R):
    t = math.radians(a)
    return CX + r * math.cos(t), CY + r * math.sin(t)

def arc(a0, a1, color):
    (x0, y0), (x1, y1) = pt(a0), pt(a1)
    large = 1 if a1 - a0 > 180 else 0
    return (f'<path d="M{x0:.1f} {y0:.1f} A{R} {R} 0 {large} 1 {x1:.1f} {y1:.1f}" '
            f'fill="none" stroke="{color}" stroke-width="{W}" stroke-linecap="butt"/>')

def needle(color):
    a = math.radians(22)
    tip = (CX + 215 * math.cos(a), CY + 215 * math.sin(a))
    n = (-math.sin(a), math.cos(a))
    b1 = (CX + 26 * n[0], CY + 26 * n[1])
    b2 = (CX - 26 * n[0], CY - 26 * n[1])
    return (f'<path d="M{b1[0]:.1f} {b1[1]:.1f} L{tip[0]:.1f} {tip[1]:.1f} L{b2[0]:.1f} {b2[1]:.1f} Z" '
            f'fill="{color}" stroke="{color}" stroke-width="10" stroke-linejoin="round"/>')

SPARK = "M392 700 L432 676 L466 690 L500 648 L536 672 L572 628 L604 652 L636 612"

def body(mono=False):
    white = "#FFFFFF"
    parts = [arc(a0, a1, white if mono else c) for a0, a1, c in SEGMENTS]
    # Tick marks inside the arc.
    for a in range(135, 406, 27):
        (x0, y0), (x1, y1) = pt(a, R - 52), pt(a, R - 80)
        parts.append(f'<line x1="{x0:.1f}" y1="{y0:.1f}" x2="{x1:.1f}" y2="{y1:.1f}" '
                     f'stroke="{white}" stroke-opacity="{1 if mono else 0.55}" stroke-width="12" stroke-linecap="round"/>')
    parts.append(f'<path d="{SPARK}" fill="none" stroke="{white if mono else "#FF8C1A"}" '
                 'stroke-width="22" stroke-linecap="round" stroke-linejoin="round"/>')
    parts.append(needle(white))
    parts.append(f'<circle cx="{CX}" cy="{CY}" r="44" fill="{white}"/>')
    parts.append(f'<circle cx="{CX}" cy="{CY}" r="18" fill="{white if mono else "#0B2545"}"/>')
    return "\n  ".join(parts)

def svg(inner, bg=None, scale=1.0):
    head = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">'
    back = f'<rect width="1024" height="1024" rx="224" fill="{bg}"/>' if bg else ""
    t = f'translate({512 * (1 - scale):.1f} {512 * (1 - scale):.1f}) scale({scale})'
    return f'{head}\n  {back}\n  <g transform="{t}">\n  {inner}\n  </g>\n</svg>\n'

open("logo.svg", "w").write(svg(body(), bg="#0B2545", scale=1.25))
open("icon-foreground.svg", "w").write(svg(body()))
open("icon-monochrome.svg", "w").write(svg(body(mono=True)))
