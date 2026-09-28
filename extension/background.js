if (typeof wanted === 'undefined') importScripts('rules.js'); // service worker; Firefox loads it via manifest

const api = globalThis.browser ?? globalThis.chrome;
const BRIDGE = 'http://127.0.0.1:47801';

// ---- Transport -------------------------------------------------------------

// 'http' = fetch the app directly. 'native' = relay through the Safari app extension,
// for when Safari hasn't been granted access to 127.0.0.1.
async function send(path, body = {}, via = 'http') {
  const { token = '' } = await api.storage.local.get('token');
  if (via === 'native') {
    return api.runtime.sendNativeMessage('id.haonlabs.hoardly', { path, token, body });
  }
  const res = await fetch(BRIDGE + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Hoardly-Token': token, 'X-Hoardly-Via': 'http' },
    body: JSON.stringify(body),
  });
  return { status: res.status, ...(await res.json()) };
}

async function sendAny(path, body) {
  try {
    return { via: 'http', ...(await send(path, body, 'http')) };
  } catch (error) {
    if (!api.runtime.sendNativeMessage) throw error;
    return { via: 'native', ...(await send(path, body, 'native')) };
  }
}

// ---- Rules -----------------------------------------------------------------

let rules = DEFAULT_RULES;
const loaded = api.storage.local.get('rules').then((stored) => { if (stored.rules) rules = stored.rules; });

async function ping() {
  try {
    const reply = await sendAny('/ping', { userAgent: navigator.userAgent });
    if (reply.rules) {
      rules = reply.rules;
      await api.storage.local.set({ rules });
    }
    return reply;
  } catch (error) {
    return { error: String(error?.message ?? error) };
  }
}

// ---- Hand-off --------------------------------------------------------------

async function cookieHeader(url) {
  try {
    return (await api.cookies.getAll({ url })).map((c) => `${c.name}=${c.value}`).join('; ');
  } catch {
    return '';
  }
}

// True once Hoardly has the download(s); false means the browser has to keep them.
async function handoff(urls, { referrer, filename } = {}) {
  const items = await Promise.all(urls.map(async (url) => ({
    url,
    cookie: await cookieHeader(url),
    filename: urls.length === 1 ? filename : undefined,
  })));
  try {
    return (await sendAny('/add', { items, referrer, userAgent: navigator.userAgent })).status === 200;
  } catch {
    return false;
  }
}

// URLs the user ⌥-clicked, or that went back to the browser because Hoardly wasn't reachable.
const allowed = new Set();
function allowOnce(url) {
  allowed.add(url);
  setTimeout(() => allowed.delete(url), 30_000);
}

// Never lose a download: if Hoardly can't take it, the browser downloads it after all.
function giveBack(url) {
  if (!api.downloads) return;
  allowOnce(url);
  api.downloads.download({ url });
}

// ---- Browser downloads (Chromium, Firefox) ---------------------------------

async function takeOver(item) {
  await loaded;
  const url = item.finalUrl || item.url;
  if (allowed.has(url) || allowed.has(item.url) || item.byExtensionId === api.runtime.id) return;
  const name = (item.filename || '').split(/[\\/]/).pop();
  if (!wanted(rules, url, name, item.totalBytes ?? item.fileSize ?? -1)) return;
  await api.downloads.cancel(item.id).catch(() => {});
  api.downloads.erase({ id: item.id }).catch(() => {});
  if (!(await handoff([url], { referrer: item.referrer, filename: name }))) giveBack(url);
}

if (api.downloads?.onDeterminingFilename) {
  // Chromium: fires after the response headers, so the real file name and size are known.
  api.downloads.onDeterminingFilename.addListener((item, suggest) => {
    suggest();
    takeOver(item);
  });
} else if (api.downloads) {
  api.downloads.onCreated.addListener(takeOver);
}

// ---- Context menu ----------------------------------------------------------

// Register on every background start: Safari doesn't reliably fire onInstalled on enable/update.
api.contextMenus.removeAll(() => {
  api.contextMenus.create({ id: 'hoardly-download', title: 'Download with Hoardly', contexts: ['link', 'image', 'video', 'audio'] });
  api.contextMenus.create({ id: 'hoardly-all', title: 'Download All Links with Hoardly', contexts: ['page'] });
});

api.contextMenus.onClicked.addListener(async (info, tab) => {
  if (info.menuItemId === 'hoardly-all') {
    const links = await api.tabs.sendMessage(tab.id, { type: 'links' }).catch(() => []);
    if (links?.length) handoff(links, { referrer: info.pageUrl });
    return;
  }
  const url = info.linkUrl ?? info.srcUrl;
  if (!(await handoff([url], { referrer: info.pageUrl }))) giveBack(url);
});

// ---- Messages from content scripts and the options page --------------------

api.runtime.onMessage.addListener((message, sender, sendResponse) => {
  switch (message?.type) {
    case 'ping':
      ping().then(sendResponse);
      return true;
    case 'config': // Safari has no downloads API, so its content script intercepts link clicks instead
      loaded.then(() => sendResponse({ rules, interceptClicks: !api.downloads }));
      return true;
    case 'allow':
      allowOnce(message.url);
      return false;
    case 'take':
      handoff([message.url], { referrer: sender.url }).then((ok) => sendResponse({ ok }));
      return true;
  }
});

api.runtime.onInstalled.addListener(ping);
api.runtime.onStartup.addListener(ping);
