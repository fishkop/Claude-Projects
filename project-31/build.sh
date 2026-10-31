#!/usr/bin/env bash
# Baut das 10-Sekunden-Video "It's Polo Time" komplett neu.
# Voraussetzungen: python3 (numpy, Pillow, scipy), node + playwright (Chromium), ffmpeg
set -euo pipefail
cd "$(dirname "$0")"

python3 scripts/cutout.py     assets/poster-red.png  assets/rider-cutout.png
python3 scripts/scene_crop.py assets/poster-gold.png assets/scene-lake.png

rm -rf build/frames
node scripts/render.js
python3 scripts/audio.py build/sfx.json build/audio.wav

mkdir -p output
# 1080x1080 (Instagram/Facebook Feed)
ffmpeg -y -loglevel error -framerate 30 -i build/frames/%04d.png -i build/audio.wav \
  -c:v libx264 -preset slow -crf 17 -pix_fmt yuv420p -movflags +faststart \
  -c:a aac -b:a 192k -shortest output/its-polo-time_1080x1080.mp4
# 1080x1920 (Reels/Stories/TikTok): quadratisches Video mittig, Rand in Markenrot
ffmpeg -y -loglevel error -i output/its-polo-time_1080x1080.mp4 \
  -vf "pad=1080:1920:0:420:color=0xfc2b00,\
drawtext=fontfile=fonts/Kaushan.ttf:text='Wir suchen neue':fontsize=92:fontcolor=0xf8f3e8:x=(w-tw)/2:y=105,\
drawtext=fontfile=fonts/Kaushan.ttf:text='Polo-Spieler!':fontsize=118:fontcolor=0xf8f3e8:x=(w-tw)/2:y=225,\
drawtext=fontfile=fonts/Anton.ttf:text='EINSTEIGER WILLKOMMEN':fontsize=78:fontcolor=0xf8f3e8:x=(w-tw)/2:y=1560,\
drawtext=fontfile=fonts/Cinzel.ttf:text='AUCH OHNE REITERFAHRUNG':fontsize=40:fontcolor=0xf8f3e8:x=(w-tw)/2:y=1700" \
  -c:v libx264 -preset slow -crf 17 -pix_fmt yuv420p -movflags +faststart \
  -c:a copy output/its-polo-time_1080x1920.mp4
ls -lh output
