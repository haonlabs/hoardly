const api = globalThis.browser ?? globalThis.chrome;
let config; // { rules, interceptClicks } from the background script
api.runtime.sendMessage({ type: 'config' }).then((c) => { config = c; }, () => {});

// ⌥-click: the browser keeps this download. mousedown, so the background knows before the download starts.
document.addEventListener('mousedown', (event) => {
  const link = event.altKey && event.target.closest?.('a[href]');
  if (link) api.runtime.sendMessage({ type: 'allow', url: link.href });
}, true);

// Safari only (no downloads API): take matching link clicks before the browser does.
document.addEventListener('click', (event) => {
  const link = event.target.closest?.('a[href]');
  if (!link || event.button !== 0 || event.altKey || !config?.interceptClicks) return;
  if (!wanted(config.rules, link.href)) return;
  event.preventDefault();
  event.stopImmediatePropagation();
  const followLink = () => { location.href = link.href; }; // Hoardly unreachable: let Safari have it
  api.runtime.sendMessage({ type: 'take', url: link.href }).then((r) => r?.ok || followLink(), followLink);
}, true);

// "Download All Links": matching links on this page, deduplicated.
api.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type !== 'links') return;
  const rules = config?.rules ?? DEFAULT_RULES;
  sendResponse([...new Set([...document.links].map((a) => a.href))].filter((url) => wanted(rules, url)));
});

// ---- Media grabber (M1, M2) -------------------------------------------------
// Off entirely on YouTube (M7): its terms forbid downloading, and so does the Chrome Web Store.
if (!isYouTube(location.hostname)) watchMedia();

function watchMedia() {
  const found = new Map(); // url → { url, kind }
  let reportTimer;

  function consider(url) {
    const kind = mediaKind(url);
    if (!kind || found.has(url)) return;
    found.set(url, { url, kind });
    clearTimeout(reportTimer);
    reportTimer = setTimeout(() => api.runtime.sendMessage({ type: 'media', items: [...found.values()] }).catch(() => {}), 300);
  }

  // Network requests catch HLS players (their <video> only has a blob: URL); elements catch plain files.
  new PerformanceObserver((list) => list.getEntries().forEach((e) => consider(e.name)))
    .observe({ type: 'resource', buffered: true });
  const scanElements = () => document.querySelectorAll('video, audio, video source, audio source')
    .forEach((el) => consider(el.currentSrc || el.src));
  document.addEventListener('loadedmetadata', scanElements, true);
  addEventListener('load', scanElements);

  // "Download video" button over whichever video is under the pointer.
  let host, button, target, hideTimer;
  addEventListener('mousemove', (event) => {
    const video = document.elementsFromPoint(event.clientX, event.clientY).find((el) => el.tagName === 'VIDEO');
    if (video && video.getBoundingClientRect().width > 200) show(video);
    else if (target && !host?.matches(':hover')) { clearTimeout(hideTimer); hideTimer = setTimeout(hide, 800); }
  }, { passive: true });

  function show(video) {
    clearTimeout(hideTimer);
    if (!host) {
      host = document.createElement('div');
      const shadow = host.attachShadow({ mode: 'closed' }); // page CSS can't restyle it
      shadow.innerHTML = `<style>
        button { all: initial; font: 600 13px -apple-system, system-ui, sans-serif; color: #fff; cursor: pointer;
                 background: rgba(20, 20, 20, .78); padding: 7px 12px; border-radius: 8px; backdrop-filter: blur(8px); }
        button:hover { background: #0a84ff; }
        button:disabled { cursor: default; background: rgba(20, 20, 20, .78); opacity: .8; }
      </style><button type="button"></button>`;
      button = shadow.querySelector('button');
      button.addEventListener('click', (event) => { event.stopPropagation(); grab(); });
      Object.assign(host.style, { position: 'fixed', zIndex: 2147483647 });
      document.documentElement.append(host);
    }
    target = video;
    const protectedVideo = !!video.mediaKeys; // EME/DRM (M6)
    button.disabled = protectedVideo;
    button.textContent = protectedVideo ? 'Protected video' : '⬇ Download video';
    const r = video.getBoundingClientRect();
    Object.assign(host.style, { top: `${Math.max(r.top, 0) + 10}px`, left: `${r.right - 170}px`, display: 'block' });
  }

  function hide() {
    if (host) host.style.display = 'none';
    target = null;
  }

  function grab() {
    const src = target?.currentSrc;
    // Safari plays HLS natively, so currentSrc may itself be the playlist; MSE players leave a blob: here.
    const direct = mediaKind(src) ? { url: src, kind: mediaKind(src) } : null;
    const stream = [...found.values()].find((m) => m.kind === 'hls'); // players load the master playlist first
    const pick = direct ?? stream;
    if (!pick) { button.textContent = 'Play the video first'; return; }
    button.textContent = 'Sent to Hoardly';
    api.runtime.sendMessage({ type: 'grab', ...pick, title: document.title })
      .then((r) => { if (!r?.ok) button.textContent = 'Hoardly isn’t running'; }, () => {});
  }
}
