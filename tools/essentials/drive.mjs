// Long-lived headless session controlled over HTTP (port 8130):
//   /keys?k=Enter,Enterx3,Escape&gap=600  -> press keys, then screenshot to cur.png
//   /shot                                  -> screenshot to cur.png
//   /eval  (POST body = JS expression)     -> JSON result
//   /reload, /log (console since last call)
import puppeteer from 'puppeteer-core';
import http from 'http';
const browser = await puppeteer.launch({ executablePath: process.env.CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: 'new',
  userDataDir: process.env.PROFILE, args: ['--enable-unsafe-swiftshader', '--use-angle=swiftshader', '--autoplay-policy=no-user-gesture-required'] });
const page = await browser.newPage();
await page.setViewport({ width: 900, height: 700 });
let logs = [];
page.on('console', m => { const t = m.text(); if (!/^(Loading|Fetched|Preload)|loadscript|Canvas2D/.test(t)) logs.push(t.slice(0, 500)); });
page.on('pageerror', e => logs.push('PAGEERR ' + (e.stack || e.message)));
await page.goto(process.env.URL || 'http://127.0.0.1:8124/');
const sleep = ms => new Promise(r => setTimeout(r, ms));
http.createServer(async (req, res) => {
  const u = new URL(req.url, 'http://x');
  let body = ''; for await (const c of req) body += c;
  try {
    let out = 'ok';
    if (u.pathname === '/keys') {
      const gap = +(u.searchParams.get('gap') || 600);
      for (const kk of u.searchParams.get('k').split(',')) {
        const [key, n] = kk.split('x');
        for (let i = 0; i < (+n || 1); i++) { await page.keyboard.down(key); await sleep(150); await page.keyboard.up(key); await sleep(gap); }
      }
      await page.screenshot({ path: 'cur.png' });
    } else if (u.pathname === '/shot') await page.screenshot({ path: 'cur.png' });
    else if (u.pathname === '/eval') out = JSON.stringify(await page.evaluate(body));
    else if (u.pathname === '/reload') await page.reload();
    else if (u.pathname === '/log') { out = logs.join('\n'); logs = []; }
    res.end(out + '\n');
  } catch (e) { res.end('ERR ' + e.message + '\n'); }
}).listen(8130);
console.log('driver ready');
