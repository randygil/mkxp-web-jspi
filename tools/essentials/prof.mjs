// CPU-profile the running game (wasm function self time) with a given save loaded.
// usage: node prof.mjs <save file> [keys after load...]   (env PROFSECS, SETTLE)
import puppeteer from 'puppeteer-core';
import fs from 'fs';
const save = process.argv[2], keys = process.argv.slice(3);
const browser = await puppeteer.launch({ executablePath: process.env.CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: 'new',
  args: ['--enable-unsafe-swiftshader', '--use-angle=swiftshader', '--autoplay-policy=no-user-gesture-required'] });
const page = await browser.newPage();
await page.setViewport({ width: 900, height: 700 });
const logs = [];
page.on('console', m => { const t = m.text(); if (/PROF|rror|xcep/.test(t) && !/loadscript/.test(t)) logs.push(t); });
const sleep = ms => new Promise(r => setTimeout(r, ms));
const press = async (k, n = 1, gap = 400) => { for (let i = 0; i < n; i++) { await page.keyboard.down(k); await sleep(150); await page.keyboard.up(k); await sleep(gap); } };
await page.goto(process.env.URL || 'http://127.0.0.1:8124/');
await sleep(3000);
const bytes = Array.from(fs.readFileSync(save));
await page.evaluate(async (b, name) => {
  await localforage.setItem(namespace + name, new Uint8Array(b));
  await localforage.setItem(namespace, { [name]: { t: Date.now() } });
}, bytes, save.split(/[\/]/).pop());
await page.reload();
await sleep(+(process.env.BOOT || 20000));
await press('Enter'); await sleep(3000); await press('Enter'); await sleep(10000);
for (const k of keys) { const [key, n] = k.split('x'); await press(key, +n || 1); }
await sleep(+(process.env.SETTLE || 3000));
const cdp = await page.createCDPSession();
await cdp.send('Profiler.enable');
await cdp.send('Profiler.setSamplingInterval', { interval: 200 });
await cdp.send('Profiler.start');
await sleep(+(process.env.PROFSECS || 6) * 1000);
const { profile } = await cdp.send('Profiler.stop');
await page.screenshot({ path: 'prof.png' });
const self = new Map(); const byId = new Map(profile.nodes.map(n => [n.id, n]));
const dt = profile.timeDeltas; let total = 0;
profile.samples.forEach((id, i) => { const n = byId.get(id); const f = n.callFrame.functionName || '(anon ' + n.callFrame.url.split('/').pop() + ')'; const d = dt[i] || 0; total += d; self.set(f, (self.get(f) || 0) + d); });
const top = [...self.entries()].sort((a, b) => b[1] - a[1]).slice(0, +(process.env.TOPN || 45));
console.log('total ms', (total / 1000).toFixed(0));
for (const [f, t] of top) console.log((100 * t / total).toFixed(1).padStart(5) + '%  ' + f.slice(0, 110));
fs.writeFileSync('prof.cpuprofile', JSON.stringify(profile));
console.log(logs.slice(-4).join('\n'));
await browser.close();
