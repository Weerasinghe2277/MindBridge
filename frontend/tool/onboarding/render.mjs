// Renders the onboarding illustrations (welcome/booking/privacy.svg, 3:2) into
// assets/images/onboarding_*.png with headless Chrome or Edge. Edit the SVGs, then run:
//   node tool/onboarding/render.mjs
// Set CHROME=<path to chrome.exe> if Chrome isn't in its usual place.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const out = path.resolve(here, '..', '..', 'assets', 'images');
const W = 1200, H = 800, SCALE = 1.5; // 1800×1200 px: sharp on 3× phones at full width

const candidates = [
  process.env.CHROME,
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/usr/bin/google-chrome',
].filter(Boolean);
const chrome = candidates.find((p) => fs.existsSync(p));
if (!chrome) throw new Error('Chrome not found. Set CHROME=<path to chrome.exe>.');

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'mb-onboarding-'));
for (const name of ['welcome', 'booking', 'privacy']) {
  const svg = fs.readFileSync(path.join(here, `${name}.svg`), 'utf8').replace('<svg ', `<svg width="${W}" height="${H}" `);
  const html = path.join(tmp, `${name}.html`);
  fs.writeFileSync(html, `<!doctype html><html><body style="margin:0;overflow:hidden">${svg}</body></html>`);
  const png = path.join(out, `onboarding_${name}.png`);
  execFileSync(chrome, [
    '--headless=new', '--disable-gpu', '--hide-scrollbars', `--user-data-dir=${path.join(tmp, 'profile')}`,
    `--window-size=${W},${H}`, `--force-device-scale-factor=${SCALE}`, `--screenshot=${png}`, pathToFileURL(html).href,
  ], { stdio: 'ignore' });
  console.log('wrote', path.relative(process.cwd(), png));
}
fs.rmSync(tmp, { recursive: true, force: true });
