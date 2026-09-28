# Hoardly Privacy Policy

*Last updated: 28 September 2026*

Hoardly (the macOS app and its browser extension) does not collect, store or share personal data with Haon Labs or anyone else. There are no accounts, analytics, advertising or tracking.

## What the extension does with your data

- **Download links and page addresses.** When a download matches your rules, or when you choose "Download with Hoardly", the extension sends the file's address and the page's address to the Hoardly app on the same Mac, over `127.0.0.1`. Nothing is sent to any other computer.
- **Cookies.** For that one download, the extension reads the cookies your browser holds for the file's website and passes them to the Hoardly app, so downloads that need you to be signed in keep working. Hoardly sends them only to that same website, as your browser would, and deletes them as soon as the download finishes (they are kept until then only so an interrupted download can resume).
- **Videos on a page.** To offer video downloads, the extension notes the addresses of media the page loads. This list stays in the browser and is cleared when you leave the page.
- **Settings.** A pairing token and your download rules are kept in the extension's local storage.

## What the app stores

The list of your downloads (addresses, file names and progress) is kept on your Mac in `~/Library/Application Support/Hoardly/`. Deleting the app and that folder removes it.

## Network access

Hoardly connects only to the servers of the files you download, and to GitHub to check for app updates.

## Contact

Questions: open an issue at https://github.com/haonlabs/hoardly/issues.
