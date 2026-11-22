"""Download raw OSM data for a bounding box via the Overpass API, as a grid of tiles.

Each tile is one JSON file; tiles already on disk are skipped, so an interrupted run can be
resumed. Normally called by tools/get_map.py; standalone use:

    python3 tools/fetch_osm.py OUT_DIR S W N E COLS ROWS
"""
import json, os, sys, time, urllib.request, urllib.parse

SERVERS = ["https://overpass-api.de/api/interpreter",
           "https://overpass.kumi.systems/api/interpreter",
           "https://overpass.private.coffee/api/interpreter"]

def query(s, w, n, e):
    b = f"({s},{w},{n},{e})"
    return f"""
[out:json][timeout:900][maxsize:2000000000];
(
  way["highway"]{b};
  way["railway"="rail"]{b};
  way["building"]{b};
  way["natural"~"^(water|coastline)$"]{b};
  relation["natural"="water"]{b};
  way["waterway"="riverbank"]{b};
  way["leisure"~"^(park|garden)$"]{b};
  way["landuse"~"^(grass|cemetery|forest)$"]{b};
  way["place"="square"]{b};
);
(._;>;);
out body;
"""

def tile_paths(out_dir, cols, rows):
    return [os.path.join(out_dir, f"tile_{r}_{c}.json") for r in range(rows) for c in range(cols)]

class ServersBusy(Exception):
    pass

def fetch_tiles(bbox, cols, rows, out_dir, report=print, max_attempts=None):
    """Download all tiles. report(done, total, message) is called as things happen.
    With max_attempts, raises ServersBusy after that many failed requests for one tile."""
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "area.json"), "w") as f:
        json.dump({"bbox": list(bbox)}, f)
    s0, w0, n0, e0 = bbox
    total = cols * rows
    done = sum(os.path.exists(p) for p in tile_paths(out_dir, cols, rows))
    report(done, total, "")
    for r in range(rows):
        for c in range(cols):
            path = os.path.join(out_dir, f"tile_{r}_{c}.json")
            if os.path.exists(path):
                continue
            s = s0 + (n0 - s0) * r / rows
            n = s0 + (n0 - s0) * (r + 1) / rows
            w = w0 + (e0 - w0) * c / cols
            e = w0 + (e0 - w0) * (c + 1) / cols
            data = urllib.parse.urlencode({"data": query(s, w, n, e)}).encode()
            attempt = 0
            while True:
                url = SERVERS[attempt % len(SERVERS)]
                host = url.split("/")[2]
                try:
                    report(done, total, f"downloading tile {done + 1} of {total} from {host}")
                    req = urllib.request.Request(url, data=data,
                                                 headers={"User-Agent": "toy-game-map-builder/0.2"})
                    with urllib.request.urlopen(req, timeout=1200) as resp:
                        body = resp.read()
                    json.loads(body)          # must be complete, valid JSON
                    with open(path + ".part", "wb") as f:
                        f.write(body)
                    os.replace(path + ".part", path)
                    done += 1
                    report(done, total, f"tile {done} of {total}: {len(body) / 1e6:.1f} MB")
                    break
                except Exception as ex:   # servers busy / timeout: exponential back-off, forever
                    wait = min(600, 20 * 2 ** min(attempt // len(SERVERS), 5))
                    why = getattr(ex, "code", None)
                    why = "server busy" if why in (429, 502, 503, 504) else str(ex)[:80]
                    attempt += 1
                    if max_attempts and attempt >= max_attempts:
                        raise ServersBusy(why)
                    for left in range(wait, 0, -1):
                        if left % 5 == 0 or left == wait:
                            report(done, total, f"{host}: {why} - retrying in {left} s")
                        time.sleep(1)
            time.sleep(2)

if __name__ == "__main__":
    out, s, w, n, e, cols, rows = sys.argv[1:8]
    fetch_tiles((float(s), float(w), float(n), float(e)), int(cols), int(rows), out,
                lambda d, t, m: print(f"[{d}/{t}] {m}", flush=True))
