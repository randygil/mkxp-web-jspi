// Boot the web build headless, stream console, screenshot at the end.
// usage: node run.mjs <seconds> [shot.png] [keys...]
import puppeteer from 'puppeteer-core';
const secs = +(process.argv[2] || 60);
const shot = process.argv[3] || 'shot.png';
const keys = process.argv.slice(4);
const browser = await puppeteer.launch({
  executablePath: process.env.CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe',
  headless: 'new', userDataDir: process.env.PROFILE || undefined,
  args: ['--enable-unsafe-swiftshader', '--use-angle=swiftshader', '--autoplay-policy=no-user-gesture-required', '--window-size=900,700'],
});
const page = await browser.newPage();
await page.setViewport({ width: +(process.env.VW||900), height: +(process.env.VH||700) });
const t0 = Date.now();
const ts = () => ((Date.now() - t0) / 1000).toFixed(1).padStart(6);
page.on('console', m => { const t = m.text(); if (!/^(Loading|Fetched|Preload)/.test(t)) console.log(ts(), m.type().slice(0,4), t.slice(0, 600)); });
page.on('pageerror', e => console.log(ts(), 'PAGEERR', (e.stack||e.message||String(e)).slice(0, 2000)));
await page.evaluateOnNewDocument(() => {
  let wrapped = false;
  const iv = setInterval(() => {
    if (window.webBgmPlay && !wrapped) { wrapped = true; const o = window.webBgmPlay;
      window.webBgmPlay = (p, v, pi) => { console.log('BGMPLAY', p, v, pi); return o(p, v, pi); }; }
    if (window.loadFileAsync && !window.__lfa) { window.__lfa = 1; const o = window.loadFileAsync;
      window.loadFileAsync = (f, b, c) => { if (/audio/i.test(f)) console.log('AUDIOLOAD', f, (window.mapping||{})[window.getMappingKey(f)]); return o(f, b, c); }; }
  }, 5);
});
page.on('requestfailed', r => console.log(ts(), 'REQFAIL', r.url()));
page.on('response', r => { if (r.status() >= 400) console.log(ts(), 'HTTP', r.status(), r.url()); });
await page.goto(process.env.URL || 'http://127.0.0.1:8124/', { waitUntil: 'load' });
let k = 0;
const end = Date.now() + secs * 1000;
while (Date.now() < end) {
  await new Promise(r => setTimeout(r, 1000));
  if (keys.length && k < keys.length && Date.now() > t0 + (+process.env.KEYSTART || 15000) + k * (+process.env.KEYGAP || 1500)) {
    const [key, n] = keys[k].split('x'); for (let i = 0; i < (+n || 1); i++) { await page.keyboard.down(key); await new Promise(r => setTimeout(r, 150)); await page.keyboard.up(key); await new Promise(r => setTimeout(r, 300)); }
    console.log(ts(), 'KEY', keys[k]); await new Promise(r => setTimeout(r, 900)); await page.screenshot({ path: 'k' + String(k).padStart(2, '0') + '.png' }); k++;
  }
}
await page.screenshot({ path: shot });
await browser.close();
