// Renders the MindBridge app icon from the SVGs in this folder into every size Android, iOS and
// web need. Edit the SVGs, then run (needs Playwright with Chromium: `npm i -g playwright`):
//   node tool/icon/render_icons.cjs
//
//   icon.svg        square icon, full bleed (iOS, legacy Android, web)
//   foreground.svg  Android adaptive-icon foreground (artwork inside the 66% safe zone)
//   background.svg  Android adaptive-icon background
//   logo.svg        the logo on its own (transparent), used inside the app by MindBridgeMark
const path = require('path');
const fs = require('fs');
const { chromium } = require('playwright');

const here = __dirname;
const app = path.resolve(here, '..', '..');
const svg = (name) => fs.readFileSync(path.join(here, name), 'utf8');
const res = (...p) => path.join(app, 'android', 'app', 'src', 'main', 'res', ...p);
const ios = (f) => path.join(app, 'ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset', f);
const web = (f) => path.join(app, 'web', f);

const densities = { mdpi: 1, hdpi: 1.5, xhdpi: 2, xxhdpi: 3, xxxhdpi: 4 };

(async () => {
  const browser = await chromium.launch(process.env.CHROMIUM ? { executablePath: process.env.CHROMIUM } : {});
  const page = await browser.newPage();

  // filter: CSS filter, e.g. 'brightness(0)' for the one-colour Android 13 themed icon.
  async function render(source, size, out, { radius = 0, filter = 'none', opaque = false } = {}) {
    await page.setViewportSize({ width: size, height: size });
    const s = source.replace('<svg ', `<svg width="${size}" height="${size}" `);
    await page.setContent(`<html><body style="margin:0;background:${opaque ? '#fff' : 'transparent'}">
      <div style="width:${size}px;height:${size}px;overflow:hidden;border-radius:${radius}px;filter:${filter}">${s}</div></body></html>`);
    fs.mkdirSync(path.dirname(out), { recursive: true });
    await page.screenshot({ path: out, omitBackground: !opaque, clip: { x: 0, y: 0, width: size, height: size } });
    console.log(path.relative(app, out));
  }

  const icon = svg('icon.svg');
  const fg = svg('foreground.svg');
  const bg = svg('background.svg');

  // Android: legacy icon (pre-8.0 phones) and adaptive layers (108 dp canvas).
  for (const [d, k] of Object.entries(densities)) {
    await render(icon, 48 * k, res(`mipmap-${d}`, 'ic_launcher.png'), { radius: 48 * k * 0.22 });
    await render(fg, 108 * k, res(`mipmap-${d}`, 'ic_launcher_foreground.png'));
    await render(bg, 108 * k, res(`mipmap-${d}`, 'ic_launcher_background.png'));
    await render(fg, 108 * k, res(`mipmap-${d}`, 'ic_launcher_monochrome.png'), { filter: 'brightness(0)' });
  }

  // iOS: every size in AppIcon.appiconset. Apple rounds the corners itself and wants no transparency.
  const contents = JSON.parse(fs.readFileSync(ios('Contents.json'), 'utf8'));
  for (const img of contents.images) {
    if (!img.filename) continue;
    const px = Math.round(parseFloat(img.size) * parseInt(img.scale, 10));
    await render(icon, px, ios(img.filename), { opaque: true });
  }

  // Web
  await render(icon, 192, web('icons/Icon-192.png'), { radius: 192 * 0.22 });
  await render(icon, 512, web('icons/Icon-512.png'), { radius: 512 * 0.22 });
  const maskable = fg.replace(/(<svg[^>]*>)/, `$1${bg.match(/<defs>[\s\S]*<\/defs>/)[0].replace('id="bg"', 'id="mbg"')}<rect width="1024" height="1024" fill="url(#mbg)"/>`);
  await render(maskable, 192, web('icons/Icon-maskable-192.png'), { opaque: true });
  await render(maskable, 512, web('icons/Icon-maskable-512.png'), { opaque: true });
  await render(icon, 32, web('favicon.png'), { radius: 7 });

  // In-app logo (assets/images/logo.png at 1x, 2x and 3x for different screen densities).
  const logo = svg('logo.svg');
  for (const [dir, k] of [['', 1], ['2.0x/', 2], ['3.0x/', 3]]) {
    await render(logo, 96 * k, path.join(app, 'assets', 'images', `${dir}logo.png`));
  }

  await browser.close();
})();
