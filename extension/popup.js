const api = globalThis.browser ?? globalThis.chrome;
const list = document.getElementById('list');
const empty = document.getElementById('empty');
const status = document.getElementById('status');

function showStatus(r) {
  if (r?.authorized) return (status.textContent = '● Connected');
  if (!r?.status) return (status.textContent = 'Hoardly isn’t running');
  status.textContent = '';
  const connect = document.createElement('button');
  connect.textContent = 'Connect to Hoardly';
  connect.addEventListener('click', async () => {
    connect.textContent = 'Check Hoardly…'; // the app shows a confirmation dialog
    showStatus(await api.runtime.sendMessage({ type: 'pair' }));
  });
  status.replaceChildren(connect);
}
api.runtime.sendMessage({ type: 'ping' }).then(showStatus);

const toggle = document.getElementById('enabled');
const hint = document.getElementById('hint');
function showEnabled(on) {
  toggle.checked = on;
  hint.textContent = on ? 'Take over downloads in this browser' : 'Off — the browser handles downloads itself';
}
toggle.addEventListener('change', () => {
  showEnabled(toggle.checked);
  api.storage.local.set({ enabled: toggle.checked });
  if (!toggle.checked) { list.replaceChildren(); showEmpty('Hoardly is turned off.'); }
});

async function setupSiteSwitch(host) {
  const { disabledHosts = [] } = await api.storage.local.get('disabledHosts');
  const box = document.getElementById('siteOn');
  box.checked = !disabledHosts.includes(host);
  document.getElementById('siteName').textContent = `Take over downloads on ${host}`;
  document.getElementById('site').hidden = false;
  box.addEventListener('change', async () => {
    const { disabledHosts = [] } = await api.storage.local.get('disabledHosts'); // re-read: another popup may have changed it
    const others = disabledHosts.filter((h) => h !== host);
    await api.storage.local.set({ disabledHosts: box.checked ? others : [...others, host] });
  });
}

(async () => {
  const { enabled } = await api.storage.local.get('enabled');
  showEnabled(enabled !== false);
  if (enabled === false) return showEmpty('Hoardly is turned off.');
  const [tab] = await api.tabs.query({ active: true, currentWindow: true });
  if (/^https?:/i.test(tab?.url ?? '')) setupSiteSwitch(new URL(tab.url).hostname);
  if (!tab?.url || isYouTube(new URL(tab.url).hostname)) {
    return showEmpty('Video downloads are turned off on YouTube.');
  }
  const found = await api.runtime.sendMessage({ type: 'tab-media', tabId: tab.id });
  if (!found?.length) return showEmpty('No video found yet. Start playing it, then open Hoardly again.');
  // Streams first; players load the master playlist before the per-quality ones.
  for (const item of [...found].sort((a, b) => (a.kind === 'hls' ? 0 : 1) - (b.kind === 'hls' ? 0 : 1))) {
    const li = document.createElement('li');
    const name = document.createElement('span');
    const path = new URL(item.url).pathname.split('/').filter(Boolean).slice(-2).join('/');
    name.textContent = item.kind === 'hls' ? tab.title || 'Stream' : path;
    name.title = item.url;
    const detail = document.createElement('small');
    detail.textContent = item.kind === 'hls' ? `HLS stream · ${path}` : 'Media file';
    name.append(detail);
    const button = document.createElement('button');
    button.textContent = 'Download';
    button.addEventListener('click', async () => {
      const r = await api.runtime.sendMessage({ type: 'grab', ...item, title: tab.title, referrer: tab.url });
      button.textContent = r?.ok ? 'Sent ✓' : 'Failed';
    });
    li.append(name, button);
    list.append(li);
  }
})();

function showEmpty(text) {
  empty.textContent = text;
  empty.hidden = false;
}
