"""Map data from a Geofabrik regional extract (.osm.pbf), as an alternative to Overpass.

Geofabrik publishes ready-made OpenStreetMap extracts as plain downloads, so this works even
when the public Overpass servers are overloaded. Reading the .pbf file needs pyosmium
(Debian/Ubuntu: sudo apt install python3-pyosmium). Normally called by tools/get_map.py.

The extract step writes the same Overpass-style JSON that tools/build_map.py reads.
"""
import importlib.util, json, os, time, urllib.request

IDF_URL = "https://download.geofabrik.de/europe/france/ile-de-france/ile-de-france-latest.osm.pbf"
UA = {"User-Agent": "toy-game-map-builder/0.2"}

def available():
    return importlib.util.find_spec("osmium") is not None

def download(url, dest, report):
    """Resumable download. report(done_mb, total_mb, message)."""
    part = dest + ".part"
    have = os.path.getsize(part) if os.path.exists(part) else 0
    req = urllib.request.Request(url, headers=dict(UA, **({"Range": f"bytes={have}-"} if have else {})))
    with urllib.request.urlopen(req, timeout=120) as r:
        if have and r.status != 206:          # server ignored the range: start over
            have = 0
        total = have + int(r.headers.get("Content-Length", 0))
        mode = "ab" if have else "wb"
        t0, got = time.time(), 0
        with open(part, mode) as f:
            while True:
                chunk = r.read(1 << 20)
                if not chunk:
                    break
                f.write(chunk)
                got += len(chunk)
                rate = got / max(time.time() - t0, 0.1) / 1e6
                left = (total - have - got) / 1e6 / max(rate, 0.01)
                report(int((have + got) / 1e6), int(total / 1e6),
                       f"{rate:.1f} MB/s, about {left / 60:.0f} min left" if left > 90 else f"{rate:.1f} MB/s")
    if total and os.path.getsize(part) < total:
        raise RuntimeError("download incomplete - run again to resume")
    os.replace(part, dest)

def relevant(t):
    return ("highway" in t or t.get("railway") == "rail" or "building" in t
            or t.get("natural") in ("water", "coastline") or t.get("waterway") == "riverbank"
            or t.get("leisure") in ("park", "garden")
            or t.get("landuse") in ("grass", "cemetery", "forest") or t.get("place") == "square")

def extract(pbf, bbox, out_json, report):
    """Everything the game needs inside bbox (S, W, N, E), as Overpass-style JSON."""
    import osmium
    S, W, N, E = bbox
    m = 0.003   # small margin, ~250 m

    class Relations(osmium.SimpleHandler):
        def __init__(self):
            super().__init__()
            self.rels, self.members = [], set()
        def relation(self, r):
            t = {tag.k: tag.v for tag in r.tags}
            if t.get("natural") == "water":
                mem = [{"type": "way", "ref": x.ref, "role": x.role} for x in r.members if x.type == "w"]
                self.rels.append({"type": "relation", "id": r.id, "members": mem, "tags": t})
                self.members.update(x["ref"] for x in mem)

    class Ways(osmium.SimpleHandler):
        def __init__(self, members):
            super().__init__()
            self.members, self.ways, self.nodes, self.seen = members, [], {}, 0
        def way(self, w):
            self.seen += 1
            if self.seen % 500000 == 0:
                report(0, 0, f"reading the regional map... {self.seen // 1000000:.1f} million ways")
            t = {tag.k: tag.v for tag in w.tags}
            if not relevant(t) and w.id not in self.members:
                return
            pts, inside = [], False
            for n in w.nodes:
                loc = n.location
                if not loc.valid():
                    continue
                lat, lon = loc.lat, loc.lon
                pts.append((n.ref, lat, lon))
                if S - m <= lat <= N + m and W - m <= lon <= E + m:
                    inside = True
            if not inside:
                return
            self.ways.append({"type": "way", "id": w.id, "nodes": [p[0] for p in pts], "tags": t})
            for ref, lat, lon in pts:
                self.nodes[ref] = (lat, lon)

    report(0, 0, "finding rivers and lakes...")
    rh = Relations()
    rh.apply_file(pbf)
    report(0, 0, "reading the regional map...")
    wh = Ways(rh.members)
    wh.apply_file(pbf, locations=True, idx="flex_mem")
    kept = {w["id"] for w in wh.ways}
    rels = [r for r in rh.rels if any(x["ref"] in kept for x in r["members"])]
    elements = [{"type": "node", "id": i, "lat": a, "lon": o} for i, (a, o) in wh.nodes.items()]
    elements += wh.ways + rels
    with open(out_json + ".part", "w") as f:
        json.dump({"elements": elements}, f, separators=(",", ":"))
    os.replace(out_json + ".part", out_json)
    report(0, 0, f"{len(wh.ways)} ways, {len(wh.nodes)} nodes, {len(rels)} water areas")
