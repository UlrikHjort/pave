"""Sea polygons from OpenStreetMap coastlines, clipped to the map box.

OSM coastline ways are drawn with the land on the left (looking along the way, north up), so
the sea is on the right. Inside the box each coastline piece runs from one point on the box
edge to another; walking a piece and then clockwise along the box edge to the start of the next
piece traces a sea polygon. Closed rings inside the box are islands (land on the left, so
counter-clockwise) or, rarely, enclosed sea.

Coordinates are game metres (x east, y south); the box is [0, W] x [0, H].
"""


def _area_northup(ring):
    """Signed area with north up (y flipped): > 0 means counter-clockwise."""
    a = 0.0
    for i in range(len(ring)):
        x0, y0 = ring[i - 1]
        x1, y1 = ring[i]
        a += x0 * (-y1) - x1 * (-y0)
    return a / 2.0


def _inside(p, W, H):
    return 0.0 <= p[0] <= W and 0.0 <= p[1] <= H


def _seg_clip(a, b, W, H):
    """Liang-Barsky: the part of segment a->b inside the box as (t0, t1), or None."""
    t0, t1 = 0.0, 1.0
    dx, dy = b[0] - a[0], b[1] - a[1]
    for p, q in ((-dx, a[0]), (dx, W - a[0]), (-dy, a[1]), (dy, H - a[1])):
        if p == 0:
            if q < 0:
                return None
        else:
            r = q / p
            if p < 0:
                t0 = max(t0, r)
            else:
                t1 = min(t1, r)
            if t0 > t1:
                return None
    return t0, t1


def _clip(chain, W, H):
    """Split a polyline into its pieces inside the box: (points, starts_on_edge, ends_on_edge)."""
    pieces, cur, cur_edge = [], None, False
    for a, b in zip(chain, chain[1:]):
        c = _seg_clip(a, b, W, H)
        if c is None:
            continue
        t0, t1 = c
        pa = (a[0] + (b[0] - a[0]) * t0, a[1] + (b[1] - a[1]) * t0)
        pb = (a[0] + (b[0] - a[0]) * t1, a[1] + (b[1] - a[1]) * t1)
        if cur is None:
            cur, cur_edge = [pa], t0 > 0.0
        cur.append(pb)
        if t1 < 1.0:                      # leaves the box here
            pieces.append((cur, cur_edge, True))
            cur = None
    if cur is not None:
        pieces.append((cur, cur_edge, False))
    return pieces


def _perim(p, W, H):
    """Position along the box edge, clockwise with north up: top edge west->east (y = 0),
    right edge north->south, bottom edge east->west, left edge south->north."""
    x, y = p
    eps = 1e-6
    if abs(y) < eps:
        return x
    if abs(x - W) < eps:
        return W + y
    if abs(y - H) < eps:
        return W + H + (W - x)
    return 2 * W + H + (H - y)


def _corners_between(t0, t1, W, H):
    """Box corners met walking clockwise from t0 to t1."""
    P = 2 * (W + H)
    corners = [(W, (W, 0.0)), (W + H, (W, H)), (2 * W + H, (0.0, H)), (P, (0.0, 0.0))]
    span = (t1 - t0) % P
    out = []
    for ct, cp in corners:
        d = (ct - t0) % P
        if 0 < d < span:
            out.append((d, cp))
    return [cp for d, cp in sorted(out)]


def _side_of(p, chains):
    """True if p is on the sea side of the nearest coastline segment."""
    best, side = None, False
    for ch in chains:
        for a, b in zip(ch, ch[1:]):
            dx, dy = b[0] - a[0], b[1] - a[1]
            L2 = dx * dx + dy * dy
            if L2 == 0:
                continue
            t = max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / L2))
            d = (a[0] + dx * t - p[0]) ** 2 + (a[1] + dy * t - p[1]) ** 2
            if best is None or d < best:
                # north-up cross product: negative = p is on the right (sea side)
                cross = dx * (-(p[1] - a[1])) - (-dy) * (p[0] - a[0])
                best, side = d, cross < 0
    return side


def sea_polygons(chains, W, H):
    """chains: coastline polylines (lists of (x, y)), in way direction. Returns (sea, islands)."""
    sea, islands, pieces = [], [], []
    for ch in chains:
        if len(ch) < 2:
            continue
        closed = ch[0] == ch[-1]
        if closed and all(_inside(p, W, H) for p in ch):
            ring = ch[:-1]
            (islands if _area_northup(ring) > 0 else sea).append(ring)
            continue
        for pts, s_edge, e_edge in _clip(ch, W, H):
            if s_edge and e_edge and len(pts) >= 2:
                pieces.append(pts)
    if pieces:
        P = 2 * (W + H)
        starts = sorted(((_perim(p[0], W, H), i) for i, p in enumerate(pieces)))
        used = [False] * len(pieces)
        for i0 in range(len(pieces)):
            if used[i0]:
                continue
            poly, i = [], i0
            while not used[i]:
                used[i] = True
                poly += pieces[i]
                t_end = _perim(pieces[i][-1], W, H)
                # next piece start clockwise from here
                nxt = min(starts, key=lambda s: ((s[0] - t_end) % P) or P)
                poly += _corners_between(t_end, nxt[0], W, H)
                i = nxt[1]
            if len(poly) >= 3:
                sea.append(poly)
    elif chains and _side_of((0.0, 0.0), chains) and not islands and not sea:
        sea.append([(0.0, 0.0), (W, 0.0), (W, H), (0.0, H)])   # the whole box is sea
    elif chains and _side_of((0.0, 0.0), chains):
        sea.append([(0.0, 0.0), (W, 0.0), (W, H), (0.0, H)])   # open sea with islands in it
    return sea, islands


def assemble(ways, nodes):
    """Join coastline ways (lists of node ids, in way direction) end to start into chains."""
    by_start = {}
    for w in ways:
        by_start.setdefault(w[0], []).append(w)
    used, chains = set(), []
    for w in ways:
        if id(w) in used:
            continue
        used.add(id(w))
        chain = list(w)
        while chain[-1] in by_start and chain[-1] != chain[0]:
            nxt = next((c for c in by_start[chain[-1]] if id(c) not in used), None)
            if nxt is None:
                break
            used.add(id(nxt))
            chain += nxt[1:]
        # also extend backwards
        by_end = {c[-1]: c for c in ways if id(c) not in used}
        while chain[0] in by_end and chain[-1] != chain[0]:
            prv = by_end.pop(chain[0])
            used.add(id(prv))
            chain = prv[:-1] + chain
        chains.append([nodes[n] for n in chain if n in nodes])
    return chains
