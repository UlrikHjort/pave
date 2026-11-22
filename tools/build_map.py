"""Convert raw OSM data (tools/fetch_osm.py or tools/geofabrik.py) into a compact game map (JSON).

    python3 tools/build_map.py data/raw/large data/raw/large/map.json [tools/cities/paris.json]

The city file gives the landmarks, the hidden anchors for secrets, the city's settings (names,
texts, cheat words) and the name of its ring road, if the map should be clipped to one.

Coordinates are local metres: x east, y south (screen-style), origin at the bbox NW corner.
Everything outside the Boulevard Peripherique is dropped; the ring itself (plus a small
margin) becomes the map boundary, stored as a polygon.
"""
import collections, glob, json, math, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import coastline  # noqa: E402

src_dir, dst = sys.argv[1], sys.argv[2]
CITY = json.load(open(sys.argv[3] if len(sys.argv) > 3 else os.path.join(HERE, "cities", "paris.json"),
                      encoding="utf-8"))
RING = CITY.get("ring_road")
S, W, N, E = json.load(open(os.path.join(src_dir, "area.json")))["bbox"]
LAT0 = (S + N) / 2
MX = 111320.0 * math.cos(math.radians(LAT0))
MY = 110540.0
WIDTH = (E - W) * MX
HEIGHT = (N - S) * MY

def proj(lat, lon):
    return ((lon - W) * MX, (N - lat) * MY)

# ---------------- load + merge tiles ----------------
nodes, ways, rels = {}, {}, {}
for path in sorted(glob.glob(os.path.join(src_dir, "tile_*.json"))):
    for e in json.load(open(path))["elements"]:
        t = e["type"]
        if t == "node":
            nodes[e["id"]] = proj(e["lat"], e["lon"])
        elif t == "way":
            ways[e["id"]] = e
        elif t == "relation":
            rels[e["id"]] = e
print(f"merged {len(nodes)} nodes, {len(ways)} ways, {len(rels)} relations", flush=True)

def r1(v): return round(v, 1)
def flat(pts): return [r1(c) for p in pts for c in p]
def way_pts(w): return [nodes[n] for n in w["nodes"] if n in nodes]

# ---------------- boundary: the Peripherique ----------------
peri = []
for w in ways.values():
    t = w.get("tags", {})
    if RING and t.get("highway") in ("motorway", "trunk") and RING in t.get("name", ""):
        peri.extend(way_pts(w))
if len(peri) < 50:
    print("no ring road in the data: the whole box is playable")
    boundary = []
    def inside(p):
        return 0 <= p[0] <= WIDTH and 0 <= p[1] <= HEIGHT
else:
    CX = sum(p[0] for p in peri) / len(peri)
    CY = sum(p[1] for p in peri) / len(peri)
    BINS = 720
    MARGIN = 45.0
    rad = [0.0] * BINS
    for x, y in peri:
        b = int((math.atan2(y - CY, x - CX) + math.pi) / (2 * math.pi) * BINS) % BINS
        rad[b] = max(rad[b], math.hypot(x - CX, y - CY))
    for _ in range(BINS):           # fill empty bins from neighbours
        if all(rad): break
        rad = [r if r else max(rad[i - 1], rad[(i + 1) % BINS]) for i, r in enumerate(rad)]
    rad = [max(rad[(i + k) % BINS] for k in range(-3, 4)) + MARGIN for i in range(BINS)]

    def radius_at(a):
        f = (a + math.pi) / (2 * math.pi) * BINS - 0.5
        i = math.floor(f); t = f - i
        return rad[i % BINS] * (1 - t) + rad[(i + 1) % BINS] * t

    def inside(p):
        x, y = p
        return math.hypot(x - CX, y - CY) <= radius_at(math.atan2(y - CY, x - CX))

    boundary = []
    for i in range(BINS):
        a = (i + 0.5) / BINS * 2 * math.pi - math.pi
        r = rad[i]
        boundary.append((min(max(CX + math.cos(a) * r, 0), WIDTH), min(max(CY + math.sin(a) * r, 0), HEIGHT)))


def any_inside(pts): return any(inside(p) for p in pts)

def clip(poly, xmin, ymin, xmax, ymax):
    """Sutherland-Hodgman clip of a polygon to a rectangle."""
    def clip_edge(pts, ins, inter):
        out = []
        for i in range(len(pts)):
            a, b = pts[i - 1], pts[i]
            ia, ib = ins(a), ins(b)
            if ib:
                if not ia: out.append(inter(a, b))
                out.append(b)
            elif ia:
                out.append(inter(a, b))
        return out
    def ix(x): return lambda a, b: (x, a[1] + (b[1] - a[1]) * (x - a[0]) / (b[0] - a[0]))
    def iy(y): return lambda a, b: (a[0] + (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]), y)
    p = poly
    p = clip_edge(p, lambda q: q[0] >= xmin, ix(xmin)) if p else p
    p = clip_edge(p, lambda q: q[0] <= xmax, ix(xmax)) if p else p
    p = clip_edge(p, lambda q: q[1] >= ymin, iy(ymin)) if p else p
    p = clip_edge(p, lambda q: q[1] <= ymax, iy(ymax)) if p else p
    return p

def simplify(pts, tol=0.3):
    """Drop points that are (almost) on the line between their neighbours."""
    out = list(pts)
    changed = True
    while changed and len(out) > 4:
        changed = False
        i = 0
        while i < len(out) and len(out) > 4:
            a, b, c = out[i - 1], out[i], out[(i + 1) % len(out)]
            dx, dy = c[0] - a[0], c[1] - a[1]
            L = math.hypot(dx, dy)
            d = abs((b[0] - a[0]) * dy - (b[1] - a[1]) * dx) / L if L > 1e-6 else math.hypot(b[0] - a[0], b[1] - a[1])
            if d < tol:
                del out[i]; changed = True
            else:
                i += 1
    return out

def area(pts):
    return abs(sum(pts[i - 1][0] * pts[i][1] - pts[i][0] * pts[i - 1][1] for i in range(len(pts)))) / 2

def is_underground(t):
    try:
        if float(t.get("layer", "0")) < 0: return True
    except ValueError: pass
    return t.get("tunnel") in ("yes", "building_passage") or t.get("indoor") not in (None, "no") \
        or t.get("location") == "underground" or "level" in t and t["level"].startswith("-")

# ---------------- roads ----------------
CAR = {"motorway": 16, "trunk": 16, "motorway_link": 8, "trunk_link": 8,
       "primary": 16, "primary_link": 10, "secondary": 13, "secondary_link": 8,
       "tertiary": 11, "tertiary_link": 8,
       "unclassified": 8, "residential": 8, "living_street": 7, "service": 5.5}
PED = {"pedestrian": 6, "footway": 2.5, "path": 2, "cycleway": 2.5, "steps": 3}
FAST = ("motorway", "trunk", "motorway_link", "trunk_link")

roads = []         # rendered
graph_ways = []    # (nodeids, oneway, width, name) for cars
ped_ways = []
for w in ways.values():
    t = w.get("tags", {})
    hw = t.get("highway")
    if not hw or t.get("area") == "yes": continue
    # covered stretches of the Peripherique are driven on the surface (keeps the ring whole)
    if is_underground(t) and not (hw in FAST and t.get("tunnel") == "yes"): continue
    pts = way_pts(w)
    if len(pts) < 2 or not any_inside(pts): continue
    if hw in CAR:
        lanes = t.get("lanes")
        width = CAR[hw]
        if lanes and lanes.isdigit():
            width = max(width * 0.6, min(int(lanes) * 3.5 + 2, 24))
        oneway = t.get("oneway") in ("yes", "1") or t.get("junction") == "roundabout" \
            or (hw in ("motorway", "motorway_link") and t.get("oneway") != "no")
        if t.get("oneway") == "-1":
            oneway = True
            w = dict(w, nodes=list(reversed(w["nodes"])))
            pts = list(reversed(pts))
        bridge = t.get("bridge") == "yes"
        roads.append({"k": "c", "w": r1(width), "b": 1 if bridge else 0, "p": flat(pts)})
        if hw != "service" or t.get("service") not in ("parking_aisle", "driveway"):
            graph_ways.append((w["nodes"], oneway, width, t.get("name", "")))
        if hw == "living_street": ped_ways.append((w["nodes"], 0))
    elif hw in PED:
        if is_underground(t): continue
        fw = t.get("footway")
        bridge = t.get("bridge") == "yes"
        if fw != "sidewalk":
            roads.append({"k": "p" if hw == "pedestrian" else "f", "w": PED[hw],
                          "b": 1 if bridge else 0, "p": flat(pts)})
        if hw != "cycleway":
            ped_ways.append((w["nodes"], 0))

# railway lines (on the surface)
for w in ways.values():
    t = w.get("tags", {})
    if t.get("railway") == "rail" and not is_underground(t):
        pts = way_pts(w)
        if len(pts) > 1 and any_inside(pts):
            roads.append({"k": "r", "w": 3.2, "b": 1 if t.get("bridge") == "yes" else 0, "p": flat(pts)})

# pedestrian areas (squares)
areas = []
for w in ways.values():
    t = w.get("tags", {})
    if t.get("highway") == "pedestrian" and t.get("area") == "yes" or t.get("place") == "square":
        pts = way_pts(w)
        if len(pts) > 3 and any_inside(pts):
            c = clip(pts, 0, 0, WIDTH, HEIGHT)
            if len(c) > 2: areas.append(flat(c))

# ---------------- graphs ----------------
def build_graph(way_list, directed):
    idx, gnodes, adj = {}, [], []
    def gi(n):
        if n not in idx:
            idx[n] = len(gnodes); gnodes.append(nodes[n]); adj.append(set())
        return idx[n]
    for item in way_list:
        oneway = item[1] if directed else False
        # split the way into runs of nodes inside the boundary
        run = []
        for n in item[0] + [None]:
            if n is not None and n in nodes and inside(nodes[n]):
                run.append(n); continue
            for a, b in zip(run, run[1:]):
                ia, ib = gi(a), gi(b)
                if ia == ib: continue
                adj[ia].add(ib)
                if not oneway: adj[ib].add(ia)
            run = []
    return gnodes, adj

def largest_component(n, adj):
    und = [set() for _ in range(n)]
    for a in range(n):
        for b in adj[a]: und[a].add(b); und[b].add(a)
    seen = [False] * n; best = set()
    for s in range(n):
        if seen[s]: continue
        stack = [s]; seen[s] = True; comp = []
        while stack:
            v = stack.pop(); comp.append(v)
            for u in und[v]:
                if not seen[u]: seen[u] = True; stack.append(u)
        if len(comp) > len(best): best = set(comp)
    return best

def largest_scc(n, adj):
    """Kosaraju, iterative: the biggest set of nodes that can all reach each other."""
    order, seen = [], [False] * n
    for s in range(n):
        if seen[s]: continue
        seen[s] = True
        stack = [(s, iter(adj[s]))]
        while stack:
            v, it = stack[-1]
            for u in it:
                if not seen[u]:
                    seen[u] = True; stack.append((u, iter(adj[u]))); break
            else:
                stack.pop(); order.append(v)
    radj = [[] for _ in range(n)]
    for a in range(n):
        for b in adj[a]: radj[b].append(a)
    comp = [-1] * n; best, best_size, c = -1, 0, 0
    for s in reversed(order):
        if comp[s] >= 0: continue
        comp[s] = c; stack = [s]; size = 0
        while stack:
            v = stack.pop(); size += 1
            for u in radj[v]:
                if comp[u] < 0: comp[u] = c; stack.append(u)
        if size > best_size: best, best_size = c, size
        c += 1
    return {v for v in range(n) if comp[v] == best}

def remap(gn, gadj, keep):
    order = sorted(keep)
    m = {o: i for i, o in enumerate(order)}
    return [gn[o] for o in order], [sorted(m[b] for b in gadj[o] if b in m) for o in order]

gn, gadj = build_graph(graph_ways, True)
cn, ca = remap(gn, gadj, largest_scc(len(gn), gadj))
# Pavements: many cities map their sidewalks as separate, loosely connected footways (or not
# at all). Add a pavement on both sides of every ordinary street, then merge path points that
# are close together, so pedestrians get one connected network.
sidewalk_ways = []
next_id = -1
for nids, oneway, width, name in graph_ways:
    pts = [nodes[n] for n in nids if n in nodes]
    if len(pts) < 2 or width > 20:
        continue
    for side in (-1.0, 1.0):
        off = width / 2.0 + 1.3
        ids = []
        for i, (x, y) in enumerate(pts):
            ax, ay = pts[max(i - 1, 0)]
            bx, by = pts[min(i + 1, len(pts) - 1)]
            dx, dy = bx - ax, by - ay
            L = math.hypot(dx, dy) or 1.0
            nodes[next_id] = (x - dy / L * off * side, y + dx / L * off * side)
            ids.append(next_id)
            next_id -= 1
        sidewalk_ways.append(ids)

def merge_close(way_lists, radius=3.5):
    """Map every path point to a representative: points within radius become one."""
    cell = {}
    rep = {}
    def key(p):
        return (int(p[0] // radius), int(p[1] // radius))
    for wl in way_lists:
        for n in wl:
            if n in rep or n not in nodes:
                continue
            x, y = nodes[n]
            kx, ky = key((x, y))
            found = None
            for gx in (kx - 1, kx, kx + 1):
                for gy in (ky - 1, ky, ky + 1):
                    for m in cell.get((gx, gy), ()):
                        mx, my = nodes[m]
                        if (mx - x) ** 2 + (my - y) ** 2 < radius * radius:
                            found = m
                            break
                    if found is not None:
                        break
                if found is not None:
                    break
            if found is None:
                cell.setdefault((kx, ky), []).append(n)
                rep[n] = n
            else:
                rep[n] = found
    return rep

all_ped = [list(n) for n, _ in ped_ways] + sidewalk_ways
rep = merge_close(all_ped)
merged_ways = []
for wl in all_ped:
    seq = []
    for n in wl:
        r = rep.get(n)
        if r is not None and (not seq or seq[-1] != r):
            seq.append(r)
    if len(seq) > 1:
        merged_ways.append((seq, 0))
pn, padj = build_graph(merged_ways, False)
pn2, pa2 = remap(pn, padj, largest_component(len(pn), padj))

# names: list of [name, flat pts] for nearest-street lookup
names = []
for nids, oneway, width, name in graph_ways:
    if name:
        pts = [nodes[n] for n in nids if n in nodes]
        if any_inside(pts): names.append([name, flat(pts)])
for w in ways.values():
    t = w.get("tags", {})
    if t.get("highway") == "pedestrian" and t.get("name") and not is_underground(t):
        pts = way_pts(w)
        if len(pts) > 1 and any_inside(pts): names.append([t["name"], flat(pts)])

# ---------------- buildings ----------------
buildings = []
for w in ways.values():
    t = w.get("tags", {})
    if "building" not in t or is_underground(t) or t.get("building") in ("roof",): continue
    pts = way_pts(w)
    if len(pts) < 4: continue
    ring = pts[:-1] if pts[0] == pts[-1] else pts
    cx = sum(p[0] for p in ring) / len(ring); cy = sum(p[1] for p in ring) / len(ring)
    if not inside((cx, cy)): continue
    c = clip(simplify(ring), 0, 0, WIDTH, HEIGHT)
    if len(c) < 3 or area(c) < 6: continue
    lv = t.get("building:levels", "")
    try: levels = float(lv.split(";")[0])
    except ValueError: levels = 6
    h = t.get("height")
    try: height = float(h.replace("m", "").strip()) if h else levels * 3.2 + 2
    except ValueError: height = levels * 3.2 + 2
    height = max(4, min(height, 60))
    special = 1 if t.get("building") in ("cathedral", "church", "palace", "museum", "government",
                                          "public", "civic") or t.get("historic") else 0
    buildings.append({"h": round(height), "s": special, "p": flat(c)})

# ---------------- water (Seine, canals, lakes) ----------------
def assemble_rings(way_ids):
    segs = [list(ways[i]["nodes"]) for i in way_ids if i in ways]
    rings = []
    while segs:
        cur = segs.pop()
        progress = True
        while cur[0] != cur[-1] and progress:
            progress = False
            for i, s in enumerate(segs):
                if s[0] == cur[-1]: cur += s[1:]
                elif s[-1] == cur[-1]: cur += list(reversed(s))[1:]
                elif s[-1] == cur[0]: cur = s + cur[1:]
                elif s[0] == cur[0]: cur = list(reversed(s)) + cur[1:]
                else: continue
                segs.pop(i); progress = True; break
        rings.append(cur)
    return rings

water, water_holes = [], []
for e in rels.values():
    if e.get("tags", {}).get("natural") != "water": continue
    for role, dest in (("outer", water), ("inner", water_holes)):
        ids = [m["ref"] for m in e["members"] if m["type"] == "way" and (m.get("role") or "outer") == role]
        for ring in assemble_rings(ids):
            pts = [nodes[n] for n in ring if n in nodes]
            if len(pts) < 3 or not any_inside(pts): continue
            c = clip(pts, -20, -20, WIDTH + 20, HEIGHT + 20)
            if len(c) > 2: dest.append(flat(c))
for w in ways.values():
    t = w.get("tags", {})
    if t.get("natural") == "water" or t.get("waterway") == "riverbank":
        pts = way_pts(w)
        if len(pts) > 3 and any_inside(pts) and not is_underground(t):
            c = clip(pts, -20, -20, WIDTH + 20, HEIGHT + 20)
            if len(c) > 2: water.append(flat(c))

# ---------------- sea (coastline) ----------------
coast_ways = [w["nodes"] for w in ways.values() if w.get("tags", {}).get("natural") == "coastline"]
if coast_ways:
    chains = coastline.assemble(coast_ways, nodes)
    sea, islands = coastline.sea_polygons(chains, WIDTH, HEIGHT)
    water += [flat(p) for p in sea]
    water_holes += [flat(p) for p in islands]
    print(f"coastline: {len(coast_ways)} ways -> {len(sea)} sea polygons, {len(islands)} islands")

# ---------------- parks, gardens, cemeteries ----------------
parks = []
for w in ways.values():
    t = w.get("tags", {})
    if t.get("leisure") in ("park", "garden") or t.get("landuse") in ("grass", "cemetery", "forest"):
        pts = way_pts(w)
        if len(pts) > 3 and any_inside(pts):
            c = clip(pts, 0, 0, WIDTH, HEIGHT)
            if len(c) > 2: parks.append(flat(c))

# ---------------- landmarks (mission spots, district names) ----------------
LANDMARKS = [tuple(x) for x in CITY["landmarks"]]
SECRETS = [tuple(x) for x in CITY.get("secrets", [])]
lm = [{"n": n, "x": r1(proj(a, o)[0]), "y": r1(proj(a, o)[1])} for n, a, o in LANDMARKS + SECRETS
      if inside(proj(a, o))]

out = {
    "w": r1(WIDTH), "h": r1(HEIGHT),
    "roads": roads, "areas": areas, "buildings": buildings,
    "water": water, "waterHoles": water_holes, "parks": parks,
    "graph": {"n": flat(cn), "a": ca},
    "ped": {"n": flat(pn2), "a": pa2},
    "names": names, "landmarks": lm, "boundary": flat(boundary),
    "meta": CITY.get("meta", {}),
}
with open(dst, "w") as f:
    json.dump(out, f, separators=(",", ":"))
print(f"world {WIDTH:.0f}x{HEIGHT:.0f} m | roads {len(roads)} bld {len(buildings)} water {len(water)}+{len(water_holes)} "
      f"parks {len(parks)} | car graph {len(cn)} nodes | ped graph {len(pn2)} nodes | names {len(names)}")
