#!/usr/bin/env python3
"""Download and build a PAVÉ world from OpenStreetMap.

    python3 tools/get_map.py              # asks which world
    python3 tools/get_map.py small        # central Paris
    python3 tools/get_map.py large        # all of Paris inside the Peripherique
    python3 tools/get_map.py copenhagen   # inner Copenhagen

The worlds are defined by the city files in tools/cities/ (one JSON file per city). Downloads
are resumable: run the same command again after an interruption. The result is data/<file>.bin;
the raw OSM download is deleted afterwards (use --keep-raw to keep it). Progress is also
written to data/raw/<world>/status.txt, which the game shows on screen.
"""
import argparse, glob, json, os, shutil, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import fetch_osm  # noqa: E402
import geofabrik  # noqa: E402

def load_worlds():
    """Every world of every city file: key -> world settings (+ the city file and its data)."""
    worlds = {}
    for path in sorted(glob.glob(os.path.join(HERE, "cities", "*.json"))):
        city = json.load(open(path, encoding="utf-8"))
        for key, w in city["worlds"].items():
            worlds[key] = dict(w, city_file=path, city=city["city"], geofabrik=city.get("geofabrik"))
    return worlds

WORLDS = load_worlds()

class Status:
    """Progress for humans (terminal) and for the game (status.txt, key=value lines)."""
    def __init__(self, path, quiet):
        self.path, self.quiet, self.last = path, quiet, ""
        self.parent = os.getppid()

    def __call__(self, stage, done=0, total=0, message="", unit=""):
        if self.quiet and os.getppid() != self.parent:
            sys.exit(1)       # started by the game, and the game is gone: stop (resumable)
        tmp = self.path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(f"stage={stage}\ndone={done}\ntotal={total}\nunit={unit}\nmessage={message}\n")
        os.replace(tmp, self.path)
        if self.quiet:
            return
        if stage == "download" and total:
            bar = "#" * (30 * done // total) + "-" * (30 - 30 * done // total)
            line = f"\r[{bar}] {done}/{total} {unit or 'parts'}  {message}"[:110].ljust(110)
            print(line, end="", flush=True)
        elif message != self.last:
            print(("\n" if self.last.startswith("[") else "") + message, flush=True)
        self.last = message if stage != "download" else "["

def ask():
    print("Which world do you want to install?\n")
    for i, (key, w) in enumerate(WORLDS.items(), 1):
        mark = "  (installed)" if os.path.exists(bin_path(key)) else ""
        print(f"  {i}) {w['title']}{mark}\n     {w['about']}\n     download: {w['download']}\n")
    while True:
        a = input(f"Choose 1-{len(WORLDS)} (or q to quit): ").strip().lower()
        if a in ("q", "quit", ""):
            sys.exit(0)
        if a.isdigit() and 1 <= int(a) <= len(WORLDS):
            return list(WORLDS)[int(a) - 1]
        if a in WORLDS:
            return a

def bin_path(world):
    return os.path.join(ROOT, "data", WORLDS[world]["file"] + ".bin")

def from_geofabrik(w, raw, status, keep):
    """Download the city's regional extract and cut the world's box out of it."""
    url = w["geofabrik"]
    pbf = os.path.join(ROOT, "data", "raw", os.path.basename(url))
    if not os.path.exists(pbf):
        status("download", 0, 0, "Downloading the regional map from Geofabrik...", unit="MB")
        geofabrik.download(url, pbf, lambda d, t, m: status("download", d, t, m, unit="MB"))
    status("extract", 0, 0, f"Cutting {w['city']} out of the regional map...")
    for name in os.listdir(raw):                      # replace any partial Overpass tiles
        if name.startswith("tile_"):
            os.remove(os.path.join(raw, name))
    with open(os.path.join(raw, "area.json"), "w") as f:
        json.dump({"bbox": list(w["bbox"])}, f)
    geofabrik.extract(pbf, w["bbox"], os.path.join(raw, "tile_geofabrik.json"),
                      lambda d, t, m: status("extract", 0, 0, m))
    if not keep:
        os.remove(pbf)

def run(cmd, log):
    with open(log, "a") as f:
        r = subprocess.run(cmd, stdout=f, stderr=subprocess.STDOUT)
    if r.returncode != 0:
        raise RuntimeError(f"{os.path.basename(cmd[1])} failed - see {log}")

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("world", nargs="?", choices=list(WORLDS))
    ap.add_argument("--keep-raw", action="store_true", help="keep the raw OSM download")
    ap.add_argument("--quiet", action="store_true", help="only write the status file (used by the game)")
    ap.add_argument("--source", choices=("auto", "overpass", "geofabrik"), default="auto",
                    help="where to get the data (auto: Geofabrik for the large world when pyosmium "
                         "is installed, otherwise Overpass, falling back to Geofabrik when it is busy)")
    args = ap.parse_args()
    world = args.world or (ask() if sys.stdin.isatty() else ap.error("which world? " + ", ".join(WORLDS)))
    w = WORLDS[world]
    raw = os.path.join(ROOT, "data", "raw", world)
    os.makedirs(raw, exist_ok=True)
    status = Status(os.path.join(raw, "status.txt"), args.quiet)
    log = os.path.join(raw, "build.log")
    try:
        free = shutil.disk_usage(raw).free / 1e9
        need = 2.0 if w.get("source") == "geofabrik" else 0.3
        if free < need:
            raise RuntimeError(f"not enough disk space: {free:.1f} GB free, about {need:.1f} GB needed")
        if not args.quiet:
            print(f"Installing {w['title']} - {w['about']}\nDownload: {w['download']}. "
                  f"You can stop at any time and run this again to resume.\n")
        source = args.source
        if source == "auto":
            source = "geofabrik" if w.get("source") == "geofabrik" and geofabrik.available() else "overpass"
        if source == "geofabrik" and not geofabrik.available():
            raise RuntimeError("pyosmium is needed for Geofabrik downloads: sudo apt install python3-pyosmium")
        if source == "overpass":
            cols, rows = w["grid"]
            try:
                fetch_osm.fetch_tiles(tuple(w["bbox"]), cols, rows, raw,
                                      lambda d, t, m: status("download", d, t, m, unit="parts"),
                                      max_attempts=9 if geofabrik.available() else None)
            except fetch_osm.ServersBusy:
                source = "geofabrik"      # Overpass keeps refusing: use the regional extract
        if source == "geofabrik":
            from_geofabrik(w, raw, status, args.keep_raw)
        status("build", 0, 0, "Building the map (roads, buildings, traffic network)...")
        t0 = time.time()
        js = os.path.join(raw, "map.json")
        run([sys.executable, os.path.join(HERE, "build_map.py"), raw, js, w["city_file"]], log)
        status("build", 0, 0, "Writing the game map...")
        out = bin_path(world)
        run([sys.executable, os.path.join(HERE, "export_bin.py"), js, out + ".tmp"], log)
        os.replace(out + ".tmp", out)
        if not args.keep_raw:
            for name in os.listdir(raw):
                if name.startswith("tile_") or name == "map.json":
                    os.remove(os.path.join(raw, name))
        status("done", 1, 1, f"{w['title']} installed ({os.path.getsize(out) / 1e6:.0f} MB, "
                             f"built in {time.time() - t0:.0f} s). Start the game with ./pave")
    except KeyboardInterrupt:
        status("error", 0, 0, "Interrupted - run the same command again to resume.")
        sys.exit(1)
    except Exception as ex:
        status("error", 0, 0, f"Failed: {ex}")
        sys.exit(1)

main()
