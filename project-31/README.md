# It's Polo Time – Recruiting-Video (10 s)

Dynamisches 10-Sekunden-Grafikvideo für den **Chiemsee Polo & Country Park**:
Es zeigt, was Polo auslöst, und sucht neue, motivierte Spieler.

## Ergebnis

| Datei | Format | Einsatz |
|---|---|---|
| `output/its-polo-time_1080x1080.mp4` | 1:1, 1080×1080, 30 fps, H.264 + AAC | Instagram-/Facebook-Feed, Website |
| `output/its-polo-time_1080x1920.mp4` | 9:16, 1080×1920 | Reels, Stories, TikTok, WhatsApp-Status |

## Storyboard

| Zeit | Szene | Inhalt |
|---|---|---|
| 0,0 – 2,1 s | **It's POLO TIME** | Ball fliegt durchs Bild, „It's“ – „POLO“ – „TIME“ schlagen mit Kamera-Shake ein, Rot mit handgezeichneten Tempo-Strichen (Logo-Stil) |
| 2,1 – 4,3 s | **Was Polo in dir weckt** | Reiter galoppiert ins Bild, Staub fliegt, Schlagworte **TEMPO · TEAMGEIST · ADRENALIN** |
| 4,3 – 6,4 s | **Wir suchen neue Polo-Spieler!** | Reiter vor Chiemsee-Panorama (Ken-Burns-Zoom), Schreibschrift wird „geschrieben“, roter Pinsel-Unterstrich |
| 6,4 – 7,8 s | **Einsteiger willkommen** | „– auch ohne Reiterfahrung –“ |
| 7,8 – 8,8 s | **Achtung, es besteht Suchtgefahr!** | Roter Pinselstrich, „Atemberaubender Sport.“ |
| 8,8 – 10,0 s | **Endcard** | Logo „It's Polo Time“, „Werde Teil des Teams!“, Chiemsee · Polo & Country Park |

Szenenwechsel per diagonaler Wischblende in den Markenfarben Rot `#fc2b00`, Navy `#14213d`, Creme `#f8f3e8`.

**Ton:** synthetisch erzeugt (`scripts/audio.py`, keine fremden Samples): 128-BPM-Beat, Bass-Puls,
Galopp-Hufschläge im Dreitakt, Whooshes auf den Blenden, Drum-Hits synchron zu den Text-Einschlägen.

## Aufbau

```
index.html            Animation (HTML/Canvas, deterministisch über renderAt(t))
assets/               Original-Grafiken + daraus erzeugte Freisteller
  logo-red.png        Logo (aus der Vorlage zugeschnitten)
  poster-red.png      Plakat rot  -> rider-cutout.png (Reiter freigestellt)
  poster-gold.png     Plakat gold -> scene-lake.png  (Reiter + See, ohne Typo)
fonts/                Anton, Kaushan Script, Cinzel, Playfair Display (SIL OFL)
scripts/cutout.py     Reiter freistellen
scripts/scene_crop.py Seeszene zuschneiden
scripts/render.js     Frames rendern (Playwright/Chromium)
scripts/audio.py      Tonspur erzeugen
build.sh              Kompletter Build -> output/
```

## Vorschau & neu bauen

- **Live-Vorschau:** `index.html` im Browser öffnen (läuft in Endlosschleife).
- **Video bauen:** `./build.sh` (benötigt python3 mit numpy/Pillow/scipy, node + playwright, ffmpeg).

Texte, Zeiten und Farben stehen oben im `<script>` bzw. `<style>` von `index.html`
(`SCENES`, `CUTS`, `SLAMS`) – die Tonspur folgt automatisch den Einschlag-Zeitpunkten.
