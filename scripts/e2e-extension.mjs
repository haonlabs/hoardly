#!/usr/bin/env node
// M3 check: the extension in a throwaway Helium profile, driven over the DevTools protocol.
// usage: node scripts/e2e-extension.mjs [/Applications/Helium.app]
// Covers: auto take-over (B4) with cookies (E6), ⌥-click bypass, "download all links" (B5),
// and the browser keeping the download when Hoardly isn't running (B6).
import { execSync, spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '..');
const browserApp = process.argv[2] ?? '/Applications/Helium.app';
const app = `${root}/build/DerivedData/Build/Products/Debug/Hoardly.app`;
const store = `${os.homedir()}/Library/Application Support/Hoardly/downloads.json`;
const work = fs.mkdtempSync(path.join(os.tmpdir(), 'hoardly-ext-'));
const [site, out, browserDownloads] = ['site', 'out', 'browser-downloads'].map((d) => fs.mkdirSync(`${work}/${d}`) ?? `${work}/${d}`);
const sh = (cmd) => execSync(cmd, { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const CDP = 9333;
let failures = 0;
const check = (ok, label) => { console.log(`${ok ? 'PASS' : 'FAIL'}: ${label}`); if (!ok) failures++; };

async function until(fn, ms = 15_000) {
  for (const end = Date.now() + ms; Date.now() < end; await sleep(250)) {
    try { const v = await fn(); if (v) return v; } catch {}
  }
  return null;
}

function cdp(wsUrl) {
  const ws = new WebSocket(wsUrl);
  const pending = new Map();
  let id = 0;
  ws.onmessage = (m) => { const msg = JSON.parse(m.data); pending.get(msg.id)?.(msg.result ?? msg); pending.delete(msg.id); };
  const opened = new Promise((r) => { ws.onopen = r; });
  return {
    call: async (method, params = {}) => { await opened; return new Promise((r) => { pending.set(++id, r); ws.send(JSON.stringify({ id, method, params })); }); },
    eval: async function (expression) {
      const r = await this.call('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
      return r.result?.value;
    },
    close: () => ws.close(),
  };
}
const targets = async () => (await fetch(`http://127.0.0.1:${CDP}/json`)).json();
const storeItems = () => (fs.existsSync(store) ? JSON.parse(fs.readFileSync(store, 'utf8')) : []);

// --- setup ------------------------------------------------------------------
for (const f of ['take.zip', 'alt.zip', 'fallback.zip', 'off.zip', 'all1.iso', 'all2.dmg']) fs.writeFileSync(`${site}/${f}`, Buffer.alloc(3_000_000, f));
fs.writeFileSync(`${site}/clip.mp4`, Buffer.alloc(200_000));
fs.writeFileSync(`${site}/master.m3u8`, '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nlow.m3u8\n');
// A stand-in for hls.js: the <video> gets a blob:, the playlist only shows up as a network request.
fs.writeFileSync(`${site}/show.html`, `<!doctype html><title>My Show: Episode 1</title><body style="margin:0">
<video src="/clip.mp4" muted style="position:absolute;left:0;top:0;width:640px;height:360px;background:#000"></video>
<script>fetch('/master.m3u8')</script>`);
fs.writeFileSync(`${site}/page.html`, `<!doctype html><script>document.cookie = "session=abc123; path=/";</script>
<a id="alt" href="/alt.zip" style="position:absolute;left:0;top:0;width:200px;height:100px;display:block">alt</a>
<a href="/all1.iso" style="margin-top:120px;display:block">1</a><a href="/all2.dmg">2</a><a href="/readme.html">not a download</a>`);

const server = spawn('python3', [`${root}/scripts/range_server.py`, site, '--port', '8768', '--cookie-log', `${work}/cookies.log`]);
sh('pkill -x Hoardly || true');
const backup = fs.existsSync(store) ? fs.readFileSync(store) : null;
fs.rmSync(store, { force: true });
sh(`defaults write id.haonlabs.hoardly downloadDirectory "${out}"`);
sh('defaults write id.haonlabs.hoardly confirmBrowserDownloads -bool false');
sh('defaults write id.haonlabs.hoardly organizeByCategory -bool false');
sh(`open "${app}"`);
await until(() => fetch('http://127.0.0.1:47801/ping', { method: 'POST' }).then((r) => r.ok));
const token = sh('defaults read id.haonlabs.hoardly bridgeToken');

// Download folder via profile prefs: CDP's Browser.setDownloadBehavior would bypass the extension's download events.
fs.mkdirSync(`${work}/profile/Default`, { recursive: true });
fs.writeFileSync(`${work}/profile/Default/Preferences`, JSON.stringify({ download: { default_directory: browserDownloads, prompt_for_download: false } }));
const browser = spawn(`${browserApp}/Contents/MacOS/${path.basename(browserApp, '.app')}`, [
  `--user-data-dir=${work}/profile`, '--no-first-run', '--no-default-browser-check',
  `--load-extension=${root}/extension`, `--remote-debugging-port=${CDP}`, 'about:blank',
], { stdio: 'ignore' });

try {
  const worker = await until(async () => (await targets()).find((t) => t.type === 'service_worker' && t.url.endsWith('/background.js')));
  check(worker, 'extension service worker running');
  const sw = cdp(worker.webSocketDebuggerUrl);
  // One-click pairing: on install the extension asks; Hoardly shows a dialog; Return = Connect.
  const clickConnect = `osascript -e 'tell application "System Events" to tell process "Hoardly" to click (first button whose title is "Connect") of (first window whose subrole is "AXDialog")'`;
  check(await until(() => { try { sh(clickConnect); return true; } catch { return false; } }), 'Hoardly asked to connect');
  const stored = await until(() => sw.eval('chrome.storage.local.get("token").then((s) => s.token)'));
  check(stored === token, 'paired by confirming the Hoardly dialog');
  const paired = await sw.eval('ping().then(JSON.stringify)');
  check(JSON.parse(paired ?? '{}').authorized, `authorized: ${paired}`);

  const page = cdp((await targets()).find((t) => t.type === 'page').webSocketDebuggerUrl);
  const go = async (url) => { await page.call('Page.enable'); await page.call('Page.navigate', { url }); await sleep(1500); };

  // B4 + E6: a matching download moves to Hoardly, with the site's cookie.
  await go('http://127.0.0.1:8768/page.html');
  await go('http://127.0.0.1:8768/take.zip');
  const taken = await until(() => storeItems().find((d) => d.url.endsWith('/take.zip') && 'completed' in d.state));
  check(taken, 'take.zip downloaded by Hoardly');
  const sentCookies = fs.readFileSync(`${work}/cookies.log`, 'utf8').split('\n').filter((l) => l.startsWith('/take.zip'));
  check(sentCookies.length && sentCookies.every((l) => l.includes('session=abc123')), 'site cookie reached the download server');
  check(taken && !taken.headers?.Cookie, 'cookie not kept on disk after the download finished');
  check(!fs.existsSync(`${browserDownloads}/take.zip`), 'browser did not also save take.zip');

  // ⌥-click: the browser keeps it.
  await go('http://127.0.0.1:8768/page.html');
  for (const type of ['mousePressed', 'mouseReleased']) {
    await page.call('Input.dispatchMouseEvent', { type, x: 50, y: 50, button: 'left', clickCount: 1, modifiers: 1 });
  }
  check(await until(() => fs.existsSync(`${browserDownloads}/alt.zip`)), '⌥-click: browser saved alt.zip');
  check(!storeItems().some((d) => d.url.endsWith('/alt.zip')), '⌥-click: Hoardly left alt.zip alone');

  // B5: "Download All Links" (same code path as the menu item, minus the click).
  const sent = await sw.eval(`(async () => {
    const [tab] = await chrome.tabs.query({ url: 'http://127.0.0.1:8768/page.html' });
    const links = await chrome.tabs.sendMessage(tab.id, { type: 'links' });
    return JSON.stringify({ links, ok: await handoff(links, { referrer: tab.url }) });
  })()`);
  check(JSON.parse(sent ?? '{}').links?.length === 3, `links collected: ${sent}`);
  check(await until(() => ['all1.iso', 'all2.dmg'].every((f) => storeItems().some((d) => d.url.endsWith(f) && 'completed' in d.state))), 'all links downloaded by Hoardly');

  // M1/M2: the playlist a page loads shows up in the popup list, named after the page.
  await go('http://127.0.0.1:8768/show.html');
  const listed = await until(() => sw.eval(`(async () => {
    const [tab] = await chrome.tabs.query({ url: 'http://127.0.0.1:8768/show.html' });
    return JSON.stringify([...(media.get(tab.id)?.values() ?? [])]);
  })()`).then((j) => (JSON.parse(j).some((m) => m.kind === 'hls') ? j : null)));
  check(listed?.includes('master.m3u8') && listed.includes('clip.mp4'), `media found: ${listed}`);
  // The overlay button over the <video>: hover, then click it (top-right corner of the video).
  await page.call('Input.dispatchMouseEvent', { type: 'mouseMoved', x: 300, y: 200 });
  await sleep(300);
  for (const type of ['mousePressed', 'mouseReleased']) {
    await page.call('Input.dispatchMouseEvent', { type, x: 640 - 170 + 30, y: 25, button: 'left', clickCount: 1 });
  }
  check(await until(() => storeItems().some((d) => d.url.endsWith('/clip.mp4'))), 'overlay button sent clip.mp4 to Hoardly');
  const streamGrab = await sw.eval(`grab({ url: 'http://127.0.0.1:8768/master.m3u8', kind: 'hls', title: 'My Show: Episode 1',
    referrer: 'http://127.0.0.1:8768/show.html' })`);
  const stream = await until(() => storeItems().find((d) => d.url.endsWith('/master.m3u8')));
  check(streamGrab && stream?.stream && stream.fileName === 'My Show Episode 1.mp4', `stream handed over as HLS: ${stream?.fileName}`);
  const onYouTube = await sw.eval(`grab({ url: 'http://127.0.0.1:8768/master.m3u8', kind: 'hls', title: 'x', referrer: 'https://www.youtube.com/watch?v=1' })`);
  check(onYouTube === false, 'refused on YouTube');

  // B7: take-over switched off for this site → the browser keeps the download.
  await sw.eval(`chrome.storage.local.set({ disabledHosts: ['127.0.0.1'] })`);
  await sleep(300);
  await go('http://127.0.0.1:8768/off.zip');
  check(await until(() => fs.existsSync(`${browserDownloads}/off.zip`)), 'site off: browser kept off.zip');
  check(!storeItems().some((d) => d.url.endsWith('/off.zip')), 'site off: Hoardly left off.zip alone');
  await sw.eval(`chrome.storage.local.set({ disabledHosts: [] })`);
  await sleep(300);

  // B6: Hoardly not running → the browser downloads it after all.
  sh('pkill -x Hoardly || true');
  await sleep(500);
  await go('http://127.0.0.1:8768/fallback.zip');
  check(await until(() => fs.existsSync(`${browserDownloads}/fallback.zip`)), 'app down: browser kept fallback.zip');

  for (const c of [sw, page]) c.close();
} finally {
  browser.kill();
  server.kill();
  sh('pkill -x Hoardly || true');
  for (const key of ['downloadDirectory', 'confirmBrowserDownloads', 'organizeByCategory']) sh(`defaults delete id.haonlabs.hoardly ${key} 2>/dev/null || true`);
  fs.rmSync(store, { force: true });
  if (backup) fs.writeFileSync(store, backup);
  fs.rmSync(work, { recursive: true, force: true });
}
console.log(failures ? `${failures} check(s) failed` : 'all checks passed');
process.exit(failures ? 1 : 0);
