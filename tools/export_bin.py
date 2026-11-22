"""Convert a map JSON (from tools/build_map.py) into a little-endian binary map read by the Ada game.

Layout (i = int32, f = float32):
  'PAVE' i:version f:W f:H
  roads:     i:n  { i:kind(0 car,1 pedestrian,2 footway) f:width i:bridge i:np f[2np] }
  areas, parks, water, holes:  i:n { i:np f[2np] }
  buildings: i:n  { f:height i:special i:np f[2np] }
  car graph, ped graph: i:n f[n] xs f[n] ys  i[n+1] start i:m i[m] adj  i[n+1] ustart i:um i[um] uadj
  names:     i:n  { i:len bytes i:np f[2np] }
  landmarks: i:n  { i:len bytes f:x f:y }
  boundary:  i:np f[2np]          (version 2: playable area; np = 0 means the whole box)
  meta:      i:n  { s:key s:value }   (version 3: the city's settings - names, texts, cheat words)

Road kind 3 is a railway line. The input is plain JSON (or the old "window.MAP=...;" form).
"""
import json, struct, sys

src, dst = sys.argv[1], sys.argv[2]
txt = open(src, encoding="utf-8").read()
M = json.loads(txt[txt.index("=") + 1:].rstrip().rstrip(";") if txt.startswith("window") else txt)
out = bytearray()
I = lambda v: out.extend(struct.pack("<i", v))
F = lambda v: out.extend(struct.pack("<f", v))
def pts(p):
    I(len(p) // 2); out.extend(struct.pack(f"<{len(p)}f", *p))
def s(t):
    b = t.encode("utf-8"); I(len(b)); out.extend(b)

out.extend(b"PAVE"); I(3); F(M["w"]); F(M["h"])
I(len(M["roads"]))
for r in M["roads"]:
    I({"c": 0, "p": 1, "f": 2, "r": 3}[r["k"]]); F(r["w"]); I(r["b"]); pts(r["p"])
for key in ("areas", "parks", "water", "waterHoles"):
    I(len(M[key]))
    for p in M[key]: pts(p)
I(len(M["buildings"]))
for b in M["buildings"]:
    F(b["h"]); I(b["s"]); pts(b["p"])
for g in (M["graph"], M["ped"]):
    n = len(g["a"]); xs = g["n"][0::2]; ys = g["n"][1::2]
    I(n); out.extend(struct.pack(f"<{n}f", *xs)); out.extend(struct.pack(f"<{n}f", *ys))
    rev = [[] for _ in range(n)]
    for a, l in enumerate(g["a"]):
        for b in l: rev[b].append(a)
    und = [sorted(set(l) | set(rev[a])) for a, l in enumerate(g["a"])]
    for adj in (g["a"], und):
        start = [0]
        for l in adj: start.append(start[-1] + len(l))
        flat = [b for l in adj for b in l]
        out.extend(struct.pack(f"<{n+1}i", *start)); I(len(flat)); out.extend(struct.pack(f"<{len(flat)}i", *flat))
I(len(M["names"]))
for name, p in M["names"]:
    s(name); pts(p)
I(len(M["landmarks"]))
for l in M["landmarks"]:
    s(l["n"]); F(l["x"]); F(l["y"])
pts(M.get("boundary", []))
meta = M.get("meta", {})
I(len(meta))
for k, v in meta.items():
    s(k); s(v)
open(dst, "wb").write(out)
print(f"wrote {dst}: {len(out)/1e6:.1f} MB")
