#!/usr/bin/env python3
"""Minimal SVG charts, written by hand.

No matplotlib, no CDN, no JavaScript.  The professor runs these scripts on
an unknown machine and the output has to open in any browser offline, so the
charts are inline SVG elements embedded directly in the HTML.  That rules out
a plotting library and costs about a hundred lines, which is a fair trade for
"it works without installing anything".
"""

PALETTE = ["#2f6f9f", "#b4552d", "#4b8b3b", "#7a4b9f", "#a8902c", "#357f7f"]


def _esc(s):
    return (str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def _nice_ticks(lo, hi, n=5):
    """Round tick values covering [lo, hi]."""
    if hi <= lo:
        hi = lo + 1
    raw = (hi - lo) / n
    mag = 10 ** len(str(int(raw))) if raw >= 1 else 0.1
    for m in (1, 2, 2.5, 5, 10):
        step = m * mag / 10 if raw < 1 else m * mag
        if step >= raw:
            break
    t, out = 0, []
    while t <= hi + step:
        if t >= lo - step:
            out.append(t)
        t += step
    return out


def grouped_bars(groups, series, values, title="", ylabel="", width=760, height=320):
    """groups: x labels.  series: legend labels.  values[s][g] -> number."""
    L, R, T, B = 64, 16, 34 if title else 12, 46
    pw, ph = width - L - R, height - T - B
    flat = [v for row in values for v in row if v is not None]
    hi = max(flat) if flat else 1
    ticks = _nice_ticks(0, hi)
    hi = max(ticks) or 1
    gw = pw / max(len(groups), 1)
    bw = gw / (len(series) + 0.6)

    p = [f'<svg viewBox="0 0 {width} {height}" width="{width}" height="{height}" '
         f'role="img" font-family="system-ui,sans-serif" font-size="11">']
    if title:
        p.append(f'<text x="{L}" y="18" font-size="13" font-weight="600">{_esc(title)}</text>')
    for t in ticks:
        y = T + ph - (t / hi) * ph
        p.append(f'<line x1="{L}" y1="{y:.1f}" x2="{L+pw}" y2="{y:.1f}" stroke="#e3e3e3"/>')
        p.append(f'<text x="{L-6}" y="{y+3:.1f}" text-anchor="end" fill="#666">'
                 f'{t:g}</text>')
    if ylabel:
        p.append(f'<text x="12" y="{T+ph/2:.0f}" fill="#666" '
                 f'transform="rotate(-90 12 {T+ph/2:.0f})" text-anchor="middle">{_esc(ylabel)}</text>')
    for gi, g in enumerate(groups):
        x0 = L + gi * gw
        for si in range(len(series)):
            v = values[si][gi]
            if v is None:
                continue
            h = (v / hi) * ph
            x = x0 + 0.3 * bw + si * bw
            y = T + ph - h
            p.append(f'<rect x="{x:.1f}" y="{y:.1f}" width="{bw*0.9:.1f}" height="{h:.1f}" '
                     f'fill="{PALETTE[si % len(PALETTE)]}"><title>{_esc(series[si])} '
                     f'{_esc(g)}: {v:g}</title></rect>')
            if h > 16:
                p.append(f'<text x="{x+bw*0.45:.1f}" y="{y-3:.1f}" text-anchor="middle" '
                         f'fill="#333" font-size="10">{v:,.0f}</text>')
        p.append(f'<text x="{x0+gw/2:.1f}" y="{T+ph+15:.0f}" text-anchor="middle">{_esc(g)}</text>')
    p.append(f'<line x1="{L}" y1="{T+ph}" x2="{L+pw}" y2="{T+ph}" stroke="#999"/>')
    for si, s in enumerate(series):
        x = L + si * 150
        p.append(f'<rect x="{x}" y="{height-18}" width="10" height="10" '
                 f'fill="{PALETTE[si % len(PALETTE)]}"/>')
        p.append(f'<text x="{x+14}" y="{height-9}">{_esc(s)}</text>')
    p.append("</svg>")
    return "".join(p)


def lines(xs, series, title="", xlabel="", ylabel="", width=760, height=340, logy=True):
    """series: list of (label, [y or None per x]).  Log y by default -- query
    times here span three orders of magnitude, and a linear axis would show
    one tall query and thirty-nine flat ones."""
    import math
    L, R, T, B = 64, 150, 34 if title else 12, 42
    pw, ph = width - L - R, height - T - B
    flat = [v for _, ys in series for v in ys if v]
    if not flat:
        return "<p><em>no data to plot</em></p>"
    lo, hi = min(flat), max(flat)
    if logy:
        lo = max(lo, 1e-2)
        f = lambda v: (math.log10(max(v, lo)) - math.log10(lo)) / max(math.log10(hi) - math.log10(lo), 1e-9)
        ticks = [10 ** e for e in range(int(math.floor(math.log10(lo))), int(math.ceil(math.log10(hi))) + 1)]
    else:
        lo = 0
        f = lambda v: (v - lo) / max(hi - lo, 1e-9)
        ticks = _nice_ticks(lo, hi)

    def X(i):
        return L + (pw * i / max(len(xs) - 1, 1))

    def Y(v):
        return T + ph - f(v) * ph

    p = [f'<svg viewBox="0 0 {width} {height}" width="{width}" height="{height}" '
         f'role="img" font-family="system-ui,sans-serif" font-size="11">']
    if title:
        p.append(f'<text x="{L}" y="18" font-size="13" font-weight="600">{_esc(title)}</text>')
    for t in ticks:
        if not (lo <= t <= hi * 1.05):
            continue
        y = Y(t)
        p.append(f'<line x1="{L}" y1="{y:.1f}" x2="{L+pw}" y2="{y:.1f}" stroke="#e3e3e3"/>')
        p.append(f'<text x="{L-6}" y="{y+3:.1f}" text-anchor="end" fill="#666">{t:g}</text>')
    for i, x in enumerate(xs):
        p.append(f'<text x="{X(i):.1f}" y="{T+ph+15:.0f}" text-anchor="middle">{_esc(x)}</text>')
    if xlabel:
        p.append(f'<text x="{L+pw/2:.0f}" y="{height-8}" text-anchor="middle" fill="#666">{_esc(xlabel)}</text>')
    if ylabel:
        p.append(f'<text x="12" y="{T+ph/2:.0f}" fill="#666" '
                 f'transform="rotate(-90 12 {T+ph/2:.0f})" text-anchor="middle">{_esc(ylabel)}</text>')
    for si, (label, ys) in enumerate(series):
        col = PALETTE[si % len(PALETTE)]
        pts = [(X(i), Y(v)) for i, v in enumerate(ys) if v]
        if len(pts) > 1:
            d = "M" + " L".join(f"{x:.1f},{y:.1f}" for x, y in pts)
            p.append(f'<path d="{d}" fill="none" stroke="{col}" stroke-width="1.8"/>')
        for x, y in pts:
            p.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="2.6" fill="{col}"/>')
        if pts:
            p.append(f'<text x="{L+pw+8}" y="{pts[-1][1]+3:.1f}" fill="{col}">{_esc(label)}</text>')
    p.append(f'<line x1="{L}" y1="{T+ph}" x2="{L+pw}" y2="{T+ph}" stroke="#999"/>')
    p.append("</svg>")
    return "".join(p)
