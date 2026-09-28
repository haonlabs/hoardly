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
