#!/bin/sh
# Renders the README screenshots and GIFs into docs/media/.
# Plays scripted scenes headless (./pave --capture), then encodes with ffmpeg.
# Usage: tools/make_media.sh [seed]     (needs ffmpeg; seed defaults to 5, chosen for good footage)
set -e
cd "$(dirname "$0")/.."
OUT=docs/media
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

gprbuild -p -P pave.gpr -q
PAVE_SEED=${1:-5} PAVE_MAP=data/paris-small.bin ./pave --capture "$TMP"   # scenes are scripted for Central Paris
mkdir -p "$OUT"

for still in title saint-sulpice; do
  ffmpeg -loglevel error -y -i "$TMP/$still.png" -vf scale=960:-1:flags=lanczos "$OUT/$still.png"
done

# 20 fps frame sequences -> 12 fps, 560 px, 48-colour GIFs (undithered: scrolling
# scenes compress far better without dither). gifsicle, if installed, squeezes further.
for scene in explosion drive chase tank boat helicopter; do
  ffmpeg -loglevel error -y -framerate 20 -i "$TMP/$scene/%04d.png" \
    -vf "fps=12,scale=560:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=48[p];[b][p]paletteuse=dither=none" \
    "$OUT/$scene.gif"
  if command -v gifsicle >/dev/null; then
    gifsicle -O3 --lossy=40 -b "$OUT/$scene.gif"
  fi
done
# the whole city, from the All of Paris minimap (only if that world is installed)
if [ -f data/paris-large.bin ]; then
  mkdir -p "$TMP/tour"
  PAVE_MAP=data/paris-large.bin ./pave --tour "$TMP/tour" > /dev/null
  ffmpeg -loglevel error -y -i "$TMP/tour/overview.png" -vf scale=1400:-1:flags=lanczos "$OUT/paris-overview.png"
fi
# Copenhagen: the whole map and Nyhavn (only if that world is installed)
if [ -f data/copenhagen.bin ]; then
  mkdir -p "$TMP/cph"
  PAVE_MAP=data/copenhagen.bin ./pave --tour "$TMP/cph" > /dev/null
  ffmpeg -loglevel error -y -i "$TMP/cph/overview.png" -vf scale=1100:-1:flags=lanczos "$OUT/copenhagen-overview.png"
  ffmpeg -loglevel error -y -i "$TMP/cph/Nyhavn.png" -vf scale=960:-1:flags=lanczos "$OUT/nyhavn.png"
fi
ls -lh "$OUT"
