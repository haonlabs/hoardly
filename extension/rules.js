// Shared by the background and content scripts: which downloads Hoardly takes from the browser (B4).
// The app sends the user's rules on /ping; these defaults cover the time before the first ping.
const DEFAULT_RULES = {
  extensions: 'zip rar 7z tar gz tgz bz2 xz iso dmg pkg exe msi apk deb rpm appimage mp4 mkv mov avi webm m4v wmv flv mp3 m4a flac wav aac ogg'.split(' '),
  minSize: 0,
};

function fileExtension(name) {
  const match = /\.([a-z0-9]{1,10})$/i.exec(name.split(/[?#]/)[0]);
  return match ? match[1].toLowerCase() : '';
}

function wanted(rules, url, filename = '', size = -1) {
  if (!/^https?:/i.test(url)) return false; // blob: and data: only exist inside the browser
  const ext = fileExtension(filename) || fileExtension(new URL(url).pathname);
  return rules.extensions.includes(ext) || (rules.minSize > 0 && size >= rules.minSize);
}

const MEDIA_FILE = /\.(mp4|m4v|webm|mov|mkv|mp3|m4a|aac|ogg|oga|flac|wav)$/i;

// 'hls' for playlists, 'file' for direct media files, null otherwise.
function mediaKind(url) {
  if (!/^https?:/i.test(url ?? '')) return null;
  const path = new URL(url).pathname;
  if (/\.m3u8$/i.test(path)) return 'hls';
  return MEDIA_FILE.test(path) ? 'file' : null;
}

function isYouTube(hostname) {
  return /(^|\.)(youtube\.com|youtu\.be|youtube-nocookie\.com)$/i.test(hostname);
}
