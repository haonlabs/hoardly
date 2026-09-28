// node scripts/test-rules.js — checks the extension's download-matching rules.
const assert = require('node:assert');
const vm = require('node:vm');
const fs = require('node:fs');
const ctx = { URL };
vm.runInNewContext(fs.readFileSync(`${__dirname}/../extension/rules.js`, 'utf8') + ';this.wanted=wanted;this.DEFAULT_RULES=DEFAULT_RULES;this.mediaKind=mediaKind;this.isYouTube=isYouTube', ctx);
const { wanted, DEFAULT_RULES: rules, mediaKind, isYouTube } = ctx;

assert(wanted(rules, 'https://x.com/file.ZIP'));
assert(wanted(rules, 'https://x.com/get.php?id=1', 'Setup.dmg'), 'server-supplied name wins');
assert(wanted(rules, 'https://x.com/a/movie.mkv?token=abc#t'), 'query and fragment ignored');
assert(!wanted(rules, 'https://x.com/page.html'));
assert(!wanted(rules, 'blob:https://x.com/uuid'), 'blob stays in the browser');
assert(!wanted(rules, 'data:application/zip;base64,AA=='));
assert(wanted({ extensions: [], minSize: 5e6 }, 'https://x.com/big.bin', '', 6e6), 'size rule');
assert(!wanted({ extensions: [], minSize: 0 }, 'https://x.com/big.bin', '', 6e9), 'size rule off');
assert.equal(mediaKind('https://x.com/a/master.m3u8?t=1'), 'hls');
assert.equal(mediaKind('https://x.com/v.MP4'), 'file');
assert.equal(mediaKind('https://x.com/seg1.ts'), null, 'stream segments are not media files');
assert.equal(mediaKind('blob:https://x.com/1'), null);
assert(isYouTube('www.youtube.com') && isYouTube('youtu.be') && isYouTube('m.youtube.com') && isYouTube('youtube-nocookie.com'));
assert(!isYouTube('notyoutube.com') && !isYouTube('vimeo.com'));
console.log('rules ok');
