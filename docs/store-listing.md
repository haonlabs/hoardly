# Store listings

| Store | Item | Status |
|---|---|---|
| Chrome Web Store | `mbnhhkccmafijmndpleaalejoomejjem` (publisher haonlabs, developedbyadifens@gmail.com) | Submitted 2026-09-28, in-depth review (broad host permissions), auto-publish on approval |
| Edge Add-ons | — | not registered |
| Firefox AMO | — | not registered |

Same package for all three stores: `scripts/package-extension.sh` → `dist/hoardly-extension-<version>.zip` (built without `nativeMessaging`, which only the Safari build uses).
Icons: `extension/icon-128.png` (Chrome, AMO), `design/icon-300.png` (Edge). Homepage: https://github.com/haonlabs/hoardly. Privacy policy: https://github.com/haonlabs/hoardly/blob/main/PRIVACY.md.

## Name
Hoardly — Download Manager for macOS

## Short description (≤ 132 characters)
Send downloads and videos to Hoardly, the fast macOS download manager with multi-connection speed and resume.

## Description
Hoardly makes downloads faster and unbreakable on your Mac. This extension connects your browser to the free Hoardly app (download it at https://github.com/haonlabs/hoardly).

• Faster: files download over many connections at once.
• Resumable: pause, lose Wi-Fi or restart your Mac — downloads pick up where they stopped.
• Automatic: files you download (archives, installers, videos, music…) go to Hoardly, with your sign-in cookies so protected downloads work. Hold ⌥ Option while clicking to keep one in the browser.
• Right-click any link → "Download with Hoardly", or "Download All Links with Hoardly" for a whole page.
• Video grabber: save videos and HLS streams from web pages as MP4. Protected (DRM) videos are not supported, and it is turned off on YouTube.

Requires the Hoardly app for macOS 14 or later. Everything stays on your Mac: no accounts, no analytics.

## Category
Productivity (Chrome, Edge) · Download Management (Firefox)

## Single purpose (Chrome)
Hand browser downloads and page videos to the Hoardly download manager app running on the same Mac.

## Permission justifications (Chrome / Edge)
| Permission | Why |
|---|---|
| `downloads` | Notice downloads the browser starts so matching ones can be handed to Hoardly, and give them back to the browser if Hoardly isn't running. |
| `cookies` | Pass the site's cookies for that single download to Hoardly so downloads that require signing in keep working. |
| `contextMenus` | "Download with Hoardly" and "Download All Links with Hoardly" menu items. |
| `storage` | Remember the pairing token and download rules. |
| Host permission `<all_urls>` | Read cookies for the download's site, collect links for "Download All Links", and find videos on the page for the video grabber. Downloads can come from any site. |

Remote code: none. Data use: none collected; see privacy policy.

## Notes for reviewers
The extension talks only to `http://127.0.0.1:47801`, the Hoardly app on the user's own Mac. To test: install the app from the Releases page, open it, then install the extension and click Connect when Hoardly asks.
