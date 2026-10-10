// Renders an SVG to a PNG of the given size with a transparent background.
// Usage: node render.js in.svg out.png size
const { chromium } = require('playwright');
const fs = require('fs');
(async () => {
  const [inp, out, size] = process.argv.slice(2);
  const s = Number(size);
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: s, height: s } });
  const svg = fs.readFileSync(inp, 'utf8').replace('width="1024" height="1024"', `width="${s}" height="${s}"`);
  await page.setContent(`<html><body style="margin:0;background:transparent">${svg}</body></html>`);
  await page.screenshot({ path: out, omitBackground: true, clip: { x: 0, y: 0, width: s, height: s } });
  await browser.close();
})();
