// Renders the app icon SVGs to PNGs at the given sizes with Playwright (see docs/development.md, App icon).
// Usage: node render.js '[["icon.svg",192,"out.png"], ...]'
const { chromium } = require('playwright');
const fs = require('fs');
const jobs = JSON.parse(process.argv[2]);
(async () => { const b = await chromium.launch(); const p = await b.newPage();
for (const [svg, size, out] of jobs) {
  const data = fs.readFileSync(svg, 'utf8');
  await p.setViewportSize({ width: size, height: size });
  await p.setContent(`<html><body style="margin:0;background:transparent"><img id="i" src="data:image/svg+xml;base64,${Buffer.from(data).toString('base64')}" style="display:block;width:${size}px;height:${size}px"></body></html>`);
  await p.waitForTimeout(80);
  await p.locator('#i').screenshot({ path: out, omitBackground: true });
}
await b.close(); })();
