const api = globalThis.browser ?? globalThis.chrome;
const BRIDGE = 'http://127.0.0.1:47801';

// 'http' = fetch the app directly (Chromium, Firefox). 'native' = relay through the Safari app extension.
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
    // Safari can't fetch the loopback bridge ("Load failed"); its app extension relays instead.
    if (!api.runtime.sendNativeMessage) throw error;
    return { via: 'native', ...(await send(path, body, 'native')) };
  }
}

// M0 spike: report which transport reaches the app from this browser.
async function pingAll() {
  const results = {};
  for (const via of ['http', 'native']) {
    try {
      results[via] = await send('/ping', { userAgent: navigator.userAgent }, via);
    } catch (error) {
      results[via] = { error: String(error?.message ?? error) };
    }
  }
  console.log('Hoardly ping', results);
  return results;
}

// Register on every background start: Safari doesn't reliably fire onInstalled on enable/update.
api.contextMenus.removeAll(() => {
  api.contextMenus.create({
    id: 'hoardly-download',
    title: 'Download with Hoardly',
    contexts: ['link', 'image', 'video', 'audio'],
  });
});
api.runtime.onInstalled.addListener(pingAll);
api.runtime.onStartup.addListener(pingAll);

api.contextMenus.onClicked.addListener((info) => {
  sendAny('/add', { url: info.linkUrl ?? info.srcUrl, referrer: info.pageUrl, userAgent: navigator.userAgent })
    .then((r) => console.log('Hoardly add', r), (e) => console.warn('Hoardly add failed', e));
});

api.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message === 'ping') {
    sendAny('/ping', { userAgent: navigator.userAgent }).then(sendResponse, (e) => sendResponse({ error: String(e?.message ?? e) }));
    return true;
  }
});
