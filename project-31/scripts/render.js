// Rendert index.html Frame fuer Frame (30 fps) nach build/frames/*.png
// und exportiert die Sound-Events nach build/sfx.json.
// Aufruf: node scripts/render.js [nurFrame-Sekunden...]
const { chromium } = require("playwright");
const path = require("path");
const fs = require("fs");

(async () => {
  const root = path.resolve(__dirname, "..");
  const out = path.join(root, "build", "frames");
  fs.mkdirSync(out, { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1080, height: 1080 } });
  await page.goto("file://" + path.join(root, "index.html") + "?render");
  await page.evaluate(() => window.ready);
  const sfx = await page.evaluate(() => window.SFX);
  fs.writeFileSync(path.join(root, "build", "sfx.json"), JSON.stringify(sfx, null, 2));

  const stage = await page.$("#stage");
  const only = process.argv.slice(2).map(Number);
  const fps = 30, total = sfx.duration * fps;
  const frames = only.length ? only.map(s => Math.round(s * fps)) : [...Array(total).keys()];
  for (const i of frames) {
    await page.evaluate(t => window.renderAt(t), i / fps);
    await stage.screenshot({ path: path.join(out, `${String(i).padStart(4, "0")}.png`) });
  }
  await browser.close();
  console.log(`${frames.length} Frames -> ${out}`);
})();
