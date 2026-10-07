const api = globalThis.browser ?? globalThis.chrome;
const input = document.getElementById('token');
const result = document.getElementById('result');

api.storage.local.get('token').then(({ token }) => { input.value = token ?? ''; });

const enabled = document.getElementById('enabled');
api.storage.local.get('enabled').then((s) => { enabled.checked = s.enabled !== false; });
api.storage.onChanged.addListener((changes) => { if (changes.enabled) enabled.checked = changes.enabled.newValue !== false; });
enabled.addEventListener('change', () => api.storage.local.set({ enabled: enabled.checked }));

function show(r) {
  result.textContent = r?.authorized ? `✅ Connected to Hoardly (via ${r.via})`
    : r?.status ? '❌ Not connected — the request was declined or the token is wrong'
    : `❌ Hoardly isn’t running (${r?.error ?? 'no response'})`;
}

document.getElementById('connect').addEventListener('click', async () => {
  result.textContent = 'Confirm in the Hoardly window…';
  show(await api.runtime.sendMessage({ type: 'pair' }));
});

document.getElementById('save').addEventListener('click', async () => {
  await api.storage.local.set({ token: input.value.trim() });
  show(await api.runtime.sendMessage({ type: 'ping' }));
});

api.runtime.sendMessage({ type: 'ping' }).then(show);
