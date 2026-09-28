const api = globalThis.browser ?? globalThis.chrome;
const list = document.getElementById('list');
const empty = document.getElementById('empty');
const status = document.getElementById('status');

api.runtime.sendMessage({ type: 'ping' }).then((r) => {
  status.textContent = r?.authorized ? '● Connected' : r?.status ? 'Not paired — open Options' : 'Hoardly isn’t running';
});

(async () => {
  const [tab] = await api.tabs.query({ active: true, currentWindow: true });
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
