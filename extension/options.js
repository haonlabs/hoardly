const api = globalThis.browser ?? globalThis.chrome;
const input = document.getElementById('token');
const result = document.getElementById('result');

api.storage.local.get('token').then(({ token }) => { input.value = token ?? ''; });

document.getElementById('save').addEventListener('click', async () => {
  await api.storage.local.set({ token: input.value.trim() });
  const r = await api.runtime.sendMessage('ping');
  result.textContent = r.authorized ? `✅ Paired with Hoardly (via ${r.via})`
    : r.status ? '❌ Token rejected — copy it again from the Hoardly window'
    : `❌ Hoardly not reachable — is the app running? (${r.error ?? 'no response'})`;
});
