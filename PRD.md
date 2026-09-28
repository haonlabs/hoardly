# PRD — Hoardly: Download Manager untuk macOS

> Versi 0.2 · 2026-09-28 · Status: Disetujui
> Nama: **Hoardly** · Bundle ID: `id.haonlabs.hoardly` · Lisensi: MIT · Minimum: macOS 14
> Distribusi app: Direct (DMG, Developer ID + notarization) · Ekstensi: Chrome Web Store, Firefox AMO, Edge Add-ons · Media grabber: masuk MVP

## 1. Context

Pengguna macOS tidak punya download manager setara IDM (Windows) yang cepat, native, dan terintegrasi ke **semua** browser — terutama Safari (tidak punya API `downloads`) dan browser Chromium alternatif seperti Helium. Alternatif yang ada (Folx, Motrix, AB Download Manager) entah berbasis Electron/JVM, tidak mendukung Safari dengan baik, atau lemah di media grabbing.

**Tujuan Hoardly:** app native Swift/SwiftUI yang (1) mengunduh lebih cepat lewat multi-segment, (2) bisa resume kapan saja, (3) otomatis menangkap download dari Safari, Chrome, Helium, Arc, Brave, Edge, Firefox, dan (4) bisa menangkap video/stream (HLS) dari halaman web.

Folder project `Hoardly/` masih kosong — ini greenfield.

## 2. Target Pengguna

| Persona | Kebutuhan utama |
|---|---|
| Power user / mantan pengguna IDM | Kecepatan multi-koneksi, antrian, resume, integrasi browser otomatis |
| Pengguna koneksi tidak stabil | Resume setelah putus / restart Mac, retry otomatis |
| Pengumpul media | Ambil video dari halaman (mp4, HLS m3u8) tanpa ekstensi terpisah |

## 3. Goals & Non-Goals

**Goals (MVP)**
- Download multi-segment dengan kecepatan ≥ 1.5× download browser biasa pada server yang mendukung `Range`.
- Resume 100% andal: pause, putus jaringan, app di-quit, atau Mac restart.
- Satu codebase ekstensi browser untuk Chromium (Chrome, Helium, Brave, Arc, Edge, Vivaldi, Opera), Firefox, dan Safari.
- Media grabber: deteksi & unduh file video langsung dan HLS tanpa DRM.

**Non-Goals (tidak dikerjakan di MVP)**
- Mac App Store build (fase berikutnya; butuh sandbox).
- BitTorrent / magnet, FTP/SFTP.
- YouTube dan situs yang butuh signature/cipher khusus; konten ber-DRM (FairPlay/Widevine) — **tidak akan pernah** didukung.
- Sinkronisasi cloud, iOS app, akun pengguna, telemetry.

## 4. Fitur & Requirements

Prioritas: **P0** = wajib MVP, **P1** = MVP jika waktu cukup, **P2** = pasca-MVP.

### 4.1 Download Engine
| ID | Requirement | Prio |
|---|---|---|
| E1 | Tambah download via paste URL, clipboard detection, drag-drop link/teks, batch (banyak URL sekaligus) | P0 |
| E2 | Multi-segment: default 8 koneksi (1–32 dapat diatur) memakai HTTP `Range`; fallback 1 koneksi bila server tidak mendukung | P0 |
| E3 | Dynamic segmentation ala IDM: segmen yang selesai mengambil alih separuh sisa segmen terbesar | P0 |
| E4 | Pause/resume; state segmen dipersist; validasi ulang via `ETag`/`Last-Modified`/`Content-Length` saat resume — bila berubah, tawarkan restart | P0 |
| E5 | Retry otomatis dengan backoff saat error jaringan; tahan terhadap perpindahan Wi-Fi | P0 |
| E6 | Header dari browser diteruskan: cookies, `Referer`, `User-Agent` (agar download yang butuh login tetap jalan) | P0 |
| E7 | HTTP Basic/Digest auth; kredensial disimpan di Keychain | P1 |
| E8 | Speed limiter global & per-download | P1 |
| E9 | Verifikasi checksum (SHA-256/MD5) opsional | P2 |
| E10 | Proxy: ikut proxy sistem (gratis dari `URLSession`) | P0 |
| E11 | File hasil diberi atribut quarantine + `kMDItemWhereFroms` (Gatekeeper tetap memeriksa file) | P0 |

### 4.2 Antrian & Penjadwalan
| ID | Requirement | Prio |
|---|---|---|
| Q1 | Batas download bersamaan (default 3), sisanya antri | P0 |
| Q2 | Kategori otomatis per ekstensi (Video, Musik, Dokumen, Arsip, Program) → subfolder di folder tujuan | P0 |
| Q3 | Penanganan nama duplikat: rename otomatis / timpa / tanya | P0 |
| Q4 | Scheduler: jam mulai/berhenti antrian | P1 |
| Q5 | Aksi setelah antrian selesai (sleep/shutdown) | P2 |

### 4.3 UI (SwiftUI)
| ID | Requirement | Prio |
|---|---|---|
| U1 | Jendela utama: sidebar (Semua, Aktif, Selesai, Antri, kategori) + tabel (nama, ukuran, progres, kecepatan, ETA, status) | P0 |
| U2 | Detail download: visual progres per segmen, URL, header, lokasi file | P1 |
| U3 | Dialog "Download baru" yang muncul saat ditangkap dari browser: nama file, folder, kategori, "Mulai/Nanti" | P0 |
| U4 | Menu bar item (kecepatan total, daftar aktif) + progres di ikon Dock | P0 |
| U5 | Notifikasi sistem saat selesai/gagal; klik → reveal in Finder | P0 |
| U6 | Settings: koneksi/segmen, folder & kategori, aturan intercept browser, limiter, pairing ekstensi | P0 |
| U7 | Shortcut keyboard, dukungan dark mode, VoiceOver dasar | P0 |

### 4.4 Integrasi Browser
| ID | Requirement | Prio |
|---|---|---|
| B1 | Ekstensi Chromium MV3 — satu build untuk Chrome, Helium, Brave, Arc, Edge, Vivaldi, Opera | P0 |
| B2 | Ekstensi Firefox (codebase yang sama, manifest berbeda) | P0 |
| B3 | Safari Web Extension dibundel di dalam Hoardly.app (dikonversi dari codebase yang sama via `xcrun safari-web-extension-converter`) | P0 |
| B4 | Auto-intercept download berdasarkan aturan: ekstensi file (zip, dmg, mp4, iso, pkg, …) dan ukuran minimum; tahan **⌥ Option** saat klik untuk melewati Hoardly | P0 |
| B5 | Context menu "Download with Hoardly" untuk link, gambar, video; "Download semua link" di halaman | P0 |
| B6 | Bila Hoardly tidak berjalan: ekstensi membuka `hoardly://` untuk meluncurkan app; bila gagal, biarkan browser yang mengunduh (tidak boleh ada download hilang) | P0 |
| B7 | Popup ekstensi: status koneksi ke app, toggle intercept on/off per situs | P1 |

**Mekanisme intercept per browser**
- **Chromium/Firefox:** `downloads.onCreated` → batalkan & hapus dari daftar browser → kirim URL + cookies + referer + UA + nama file ke app.
- **Safari (tidak punya `downloads` API):** content script menangkap klik link yang cocok aturan B4 (`preventDefault`) + context menu. Cookies diambil via `browser.cookies`. Keterbatasan ini didokumentasikan ke pengguna (download yang dipicu JS/redirect server mungkin tidak tertangkap → pakai context menu).

### 4.5 Media Grabber
| ID | Requirement | Prio |
|---|---|---|
| M1 | Deteksi media di halaman: `<video>/<audio>` src, plus `PerformanceObserver` (resource timing) untuk URL `.m3u8`, `.mp4`, `.webm`, `.mp3` — satu cara yang bekerja di semua browser termasuk Safari; `webRequest` sebagai tambahan di Chromium/Firefox | P0 |
| M2 | Tombol/overlay "Download video" di dekat video + daftar media di popup ekstensi | P0 |
| M3 | HLS: parse master playlist → pilih kualitas → unduh segmen paralel → gabung. Dukung AES-128 (bukan DRM) | P0 |
| M4 | Output HLS: segmen fMP4 digabung langsung ke `.mp4`; segmen MPEG-TS di-remux ke `.mp4` dengan `AVAssetExportSession` passthrough (terbukti di M0; ffmpeg hanya cadangan bila gagal di macOS 14) | P0 |
| M5 | DASH (`.mpd`) | P2 |
| M6 | Deteksi DRM → tampilkan "tidak didukung", jangan coba unduh | P0 |
| M7 | Blocklist domain YouTube: content script & deteksi media tidak aktif sama sekali di sana (lihat bagian 10) | P0 |

## 5. Arsitektur

```
┌──────────── Browser ────────────┐        ┌──────────────── Hoardly.app ────────────────┐
│ Ekstensi (Chromium/Firefox)     │  HTTP  │ LocalBridge (NWListener 127.0.0.1 + token)  │
│  background: downloads, menus   ├───────►│        │                                     │
│  content: link & media sniffing │        │        ▼                                     │
├─────────────────────────────────┤        │ DownloadManager (antrian, scheduler)         │
│ Safari Web Extension            │ native │        │                                     │
│  (appex di dalam Hoardly.app)   ├─msg───►│        ▼                                     │
└─────────────────────────────────┘        │ Engine: SegmentedDownload (URLSession Range) │
                                           │         HLSDownload (playlist + segmen)      │
            hoardly://add?url=…  ─────────►│ Store: JSON Codable di Application Support   │
                                           │ UI: SwiftUI (window, menu bar, Settings)     │
                                           └──────────────────────────────────────────────┘
```

**Keputusan teknis**
- **Bahasa/UI:** Swift 6 + SwiftUI, target **macOS 14+**. Tanpa Electron.
- **Engine:** `URLSession` (native; dapat HTTP/2, proxy sistem, TLS gratis). Tiap segmen = data task dengan header `Range`, ditulis ke `FileHandle` pada offset-nya ke satu file `.hoardly-part`, rename saat selesai. Tidak pakai aria2/libcurl.
- **Transport browser → app:** satu jalur untuk semua browser non-Safari: **HTTP lokal** di `127.0.0.1` (port tetap, mis. 47801, dengan 2 port cadangan) via `Network.framework`. Setiap request wajib membawa **token pairing** (dibuat app, disalin sekali ke ekstensi). Menghindari manifest native-messaging per-browser yang lokasinya berbeda-beda (Helium, Arc, Brave, dst.).
- **Safari:** `browser.runtime.sendNativeMessage` → `SafariWebExtensionHandler` di appex (sandboxed, `network.client`) → POST ke LocalBridge. ✅ Terbukti di M0; tidak butuh izin website dari pengguna.
- **Persistensi:** file JSON (`Codable`) untuk daftar download + state segmen. SwiftData/SQLite hanya jika riwayat > puluhan ribu item terbukti lambat.
- **Update app:** Sparkle (standar untuk distribusi DMG).
- **Ekstensi:** JavaScript biasa tanpa framework/bundler; satu folder `extension/src` + tiga `manifest.json` (chromium, firefox, safari). `globalThis.browser ?? chrome` untuk kompatibilitas API.

**Struktur repo yang diusulkan**
```
Hoardly/
  Hoardly.xcodeproj
  Hoardly/                 # app target: App, UI, DownloadManager, Engine, LocalBridge, Store
  HoardlySafariExtension/  # appex target (hasil converter, resource menunjuk ke extension/src)
  extension/
    manifest.json, *.js    # satu manifest MV3 untuk Chromium + Safari; Firefox butuh varian `background.scripts` (M3)
  HoardlyTests/
```

## 6. Non-Functional Requirements
- **Performa:** mampu menjenuhkan link 1 Gbps; CPU < 15% saat download penuh; RAM < 150 MB dengan 10 download aktif.
- **Keandalan:** tidak ada file korup setelah kill -9 di tengah download (state di-flush berkala, file final hanya muncul setelah selesai & terverifikasi ukuran).
- **Keamanan:** LocalBridge hanya bind ke loopback + wajib token + tolak `Origin` non-ekstensi; semua file diberi quarantine; Hardened Runtime + notarization; kredensial hanya di Keychain.
- **Privasi:** tidak ada telemetry/analytics; cookies hanya dipakai untuk request download terkait dan tidak disimpan setelah selesai.
- **Lokalisasi:** Bahasa Indonesia & Inggris.

## 7. Milestones

| Milestone | Isi | Exit criteria |
|---|---|---|
| **M0 – Spike (1 mgg)** | Uji Safari appex → app; muat ekstensi di Helium & Arc; uji remux TS→MP4 (ffmpeg vs alternatif) | Keputusan transport Safari & remux final |
| **M1 – Engine (2–3 mgg)** | SegmentedDownload, dynamic split, resume, retry, persistensi | Unduh 5 GB, kill app di 50%, resume, SHA-256 identik |
| **M2 – App UI (2 mgg)** | Jendela utama, dialog tambah, antrian, kategori, menu bar, notifikasi, Settings | Alur pakai lengkap tanpa browser |
| **M3 – Ekstensi Chromium & Firefox (2 mgg)** | LocalBridge + pairing, intercept, context menu, fallback B6 | Download dari Chrome, Helium, Firefox tertangkap otomatis dengan cookies |
| **M4 – Safari (1–2 mgg)** | Appex, klik-intercept, context menu | Download dari Safari tertangkap via klik & context menu |
| **M5 – Media Grabber (2–3 mgg)** | Deteksi media, overlay, HLS + AES-128, remux | Unduh stream HLS publik (tanpa DRM) jadi `.mp4` yang bisa diputar QuickTime |
| **M6 – Rilis (1–2 mgg)** | Sparkle, notarization, DMG, onboarding (pasang ekstensi + pairing); submit ekstensi ke Chrome Web Store, Firefox AMO, Edge Add-ons (review bisa beberapa hari — submit lebih awal); rilis source + binary di GitHub | DMG ter-notarize terpasang bersih di Mac baru; ekstensi lolos review di ketiga store |

Estimasi total: ~12–15 minggu untuk 1 developer.

## 8. Metrik Keberhasilan
- Kecepatan rata-rata ≥ 1.5× browser pada server yang mendukung `Range` (diukur di 5 mirror publik).
- Tingkat resume sukses ≥ 99% pada uji putus-sambung.
- ≥ 95% download dari 3 browser utama (Safari, Chrome, Helium) tertangkap pada suite uji situs.
- Crash-free session ≥ 99.5%.

## 9. Risiko & Mitigasi
| Risiko | Mitigasi |
|---|---|
| Safari tidak punya `downloads` API → intercept tidak lengkap | Klik-intercept + context menu; dokumentasikan; download browser tetap jalan jika tidak tertangkap |
| Safari extension diblokir mengakses `http://127.0.0.1` | Jalur native messaging via appex (spike M0) |
| Helium (ungoogled-chromium) mungkin terbatas akses Chrome Web Store | Verifikasi di M0; siapkan `.crx`/load-unpacked + panduan |
| Situs mengikat URL ke sesi/IP/cookie berumur pendek | Teruskan cookies+referer+UA; saat 403 di resume, minta ekstensi refresh URL (P1) |
| Lisensi ffmpeg | Build LGPL, dynamic link, cantumkan lisensi; atau hindari bila fMP4 cukup |
| Isu hukum media grabber | Tolak DRM, tidak menargetkan YouTube, ToS di onboarding |
| Ekstensi ditolak store (kebijakan Chrome Web Store melarang pengunduh YouTube) | Media grabber menonaktifkan diri di domain YouTube; deskripsi listing jelas; permission seminimal mungkin |

## 10. Keputusan
| Topik | Keputusan | Dampak |
|---|---|---|
| Nama & bundle ID | Hoardly · `id.haonlabs.hoardly` (appex: `id.haonlabs.hoardly.SafariExtension`) | Dipakai di Xcode project, Keychain service, URL scheme `hoardly://` |
| Model | Open-source, lisensi **MIT** | Repo publik di GitHub + file `LICENSE`; ffmpeg harus build LGPL + dynamic link; Sparkle (MIT) aman |
| Minimum macOS | 14 | Boleh pakai `@Observable`, `SettingsLink`, SwiftUI `Table` terbaru |
| Ekstensi | Dipublikasikan ke Chrome Web Store, Firefox AMO, Edge Add-ons di MVP | Butuh akun developer tiap store; listing + privacy policy; Safari ikut dalam DMG |
| YouTube | Media grabber **dinonaktifkan total** di domain YouTube (`youtube.com`, `youtu.be`, `youtube-nocookie.com`, `m.youtube.com`) | Tidak ada overlay/deteksi di sana; syarat lolos Chrome Web Store |

## 11. Hasil Spike M0 (2026-09-28)
| Uji | Hasil | Keputusan |
|---|---|---|
| Project Xcode: app + `HoardlySafariExtension` + `HoardlyTests`, synchronized folders | ✅ build & test lulus | Struktur repo final |
| LocalBridge `127.0.0.1:47801` + token + Origin allowlist | ✅ curl: 200/401/403/400 sesuai | Dipakai di M3 |
| Helium 0.18 (Chromium 154) → `fetch` ke bridge | ✅ | Jalur `http` untuk semua Chromium |
| Chrome 154 | ⚠️ `--load-extension` diblokir Chrome bermerek; engine identik dengan Helium | Uji manual (Load unpacked) / Web Store |
| Safari 27 → bridge | ✅ native messaging (selalu jalan); ✅ `fetch` langsung setelah pengguna mengizinkan situs | **`http` dulu, fallback `native`** — sudah di `background.js` |
| Safari context menu | ❌ tidak muncul dengan `host_permissions` hanya `127.0.0.1`; ✅ muncul dengan `<all_urls>` + izin situs; menu harus didaftarkan setiap background start | Manifest pakai `<all_urls>` (juga dibutuhkan untuk cookies & media grabber); justifikasi untuk review store di M6 |
| "Download with Hoardly" dari Safari (MediaFire) | ✅ URL diterima app via `/add` | Alur browser → app terbukti end-to-end |
| Safari + app ad-hoc signed | ⚠️ Ekstensi baru muncul setelah "Allow Unsigned Extensions" lalu registrasi ulang | Rilis wajib Developer ID |
| Remux MPEG-TS → MP4 dengan AVFoundation (passthrough) | ✅ 3 segmen HLS → MP4 30 dtk, video+audio | **Tanpa ffmpeg**, dengan syarat lolos uji di macOS 14 |

**Sisa dari M0:** verifikasi remux AVFoundation di macOS 14 (VM); Firefox & Arc tidak terpasang, diuji di M3.

## 12. Hasil M1 — Engine (2026-09-28)
| Uji | Hasil |
|---|---|
| 5 GB, `kill -9` di 50%, relaunch | ✅ SHA-256 identik, quarantine + Where-From terpasang (`scripts/e2e-resume.sh 5120`) |
| Koneksi diputus tiap 3–5 MB (`--drop`) | ✅ retry + dynamic split (hingga 25 segmen), hash identik |
| Server tanpa `Range` (`--no-range`) | ✅ fallback 1 koneksi, restart dari 0 setelah kill, hash identik |
| Server membatasi koneksi (`--max-conns 3`, 429 + `Retry-After`) | ✅ 1.9× lebih cepat dari curl |
| speedtest.tele2.net (HTTP/1.1) | ✅ 1.4–6.8× lebih cepat dari curl (jaringan berisik) |
| proof.ovh.net (HTTP/2, rate-limit request) | ⚠️ 0.76× curl: ledakan 8 request awal memicu 429; engine turun ke ≤4 stream dan berhenti memecah |

**Temuan penting**
- **HTTP/2 multiplexing:** satu `URLSession` menggabungkan semua range ke satu koneksi TCP → tidak ada percepatan. Solusi: satu session per segmen.
- **HTTP/3:** setelah `alt-svc` ter-cache, CFNetwork pindah ke HTTP/3 yang hanya 0.2 MB/s di OVH (h2: 6 MB/s). Solusi: session `.ephemeral` (cache alt-svc tidak dipersist).
- **Range terbuka** (`bytes=N-`) dipakai agar segmen yang belum tersentuh bisa dilebur ke stream yang berjalan saat server membatasi koneksi.
- **ATS** dimatikan untuk app (`NSAllowsArbitraryLoads`) — download manager harus bisa unduh `http://`. Error permanen (ATS, TLS, URL salah) langsung gagal, tidak di-retry.

**Tindak lanjut (M2+):** ramp-up koneksi bertahap untuk server ber-rate-limit (OVH); pilih folder/nama sebelum mulai (U3); hapus download dari daftar.

## 13. Hasil M2 — App UI (2026-09-28)
| Req | Status |
|---|---|
| U1 jendela utama: sidebar filter + kategori dengan badge, tabel Name/Size/Progress/Speed/Time Left, context menu, double-click (buka file / pause-resume) | ✅ diverifikasi via screenshot |
| U3 panel "New Download" (mengambang di atas browser): alamat, nama file, folder, Start / Download Later | ✅ screenshot; muncul dari bridge maupun ⌘N |
| U4 menu bar (kecepatan total + daftar aktif) & Dock (badge + bar progres) | ✅ dibangun; popover menu bar belum terverifikasi otomatis |
| U5 notifikasi selesai/gagal, klik → Finder | ✅ dibangun |
| U6 Settings: folder, kategori, jumlah download bersamaan, koneksi, konfirmasi browser, token | ✅ screenshot |
| U7 shortcut ⌘N, ⌫ hapus, ⌘, settings; dark mode; label aksesibilitas | ✅ |
| Q1 antrean dari Settings; Q2 subfolder kategori | ✅ diuji dengan 5 file demo |
| Q3 nama duplikat | ⚠️ baru rename otomatis; opsi timpa/tanya belum |
| E1 paste dari clipboard, drag-drop link, banyak URL sekaligus | ✅ |
| Hapus download (partial dihapus, file selesai opsional ke Trash) | ✅ |
| Unit test host tidak lagi me-resume antrean pengguna | ✅ |

**Belum:** lokalisasi Bahasa Indonesia (string sudah siap untuk String Catalog), speed limiter (E8), scheduler (Q4).

## 14. Hasil M3 — Ekstensi browser (2026-09-28)
| Req | Helium (otomatis, `scripts/e2e-extension.mjs`) | Safari (manual) |
|---|---|---|
| B4 ambil alih download sesuai aturan (ekstensi file / ukuran minimum) | ✅ via `downloads.onDeterminingFilename` | ✅ via intercept klik (content script) |
| E6 cookies + referrer + UA ikut ke app | ✅ `session=abc123` terkirim | ✅ |
| ⌥-klik → browser yang unduh | ✅ | ✅ |
| B5 context menu + "Download All Links" (panel berisi daftar) | ✅ | ✅ |
| B6 app tidak berjalan → browser tetap mengunduh | ✅ | ✅ (klik diteruskan ke Safari) |

**Keputusan**
- Aturan intercept diatur di app (Settings → Browsers) dan dikirim ke ekstensi lewat `/ping` — satu tempat untuk semua browser.
- B6: membuka `hoardly://` dari ekstensi tidak bisa dideteksi berhasil/gagalnya, jadi fallback-nya selalu "browser yang unduh" + opsi **Open Hoardly at login** (SMAppService).
- Satu `manifest.json` untuk semua browser: `background.service_worker` (Chromium, Safari) + `background.scripts` (Firefox) + `browser_specific_settings.gecko`.
- `/add` menerima `items[]` dengan cookie per URL; nama file dari server/browser disanitasi.

**Belum:** uji Firefox & Arc (tidak terpasang), Chrome manual (Load unpacked), B7 popup per-situs.

## 15. Hasil M4 & M5 — Safari & Media Grabber (2026-09-28)
**M4 (Safari)** sudah tercakup di M3: appex di dalam app, intercept klik, context menu — diuji manual.

| Req | Hasil |
|---|---|
| M1 deteksi media: `PerformanceObserver` (request `.m3u8`/file media) + elemen `<video>/<audio>` | ✅ Helium otomatis, Safari manual |
| M2 tombol "⬇ Download video" di atas video (shadow DOM) + popup daftar media + badge jumlah | ✅ |
| M3 HLS: master → pilih kualitas (Picker di panel, default tertinggi) → segmen paralel → gabung; AES-128; fMP4 `EXT-X-MAP` + byte range; audio rendition terpisah | ✅ `scripts/e2e-hls.sh`: TS, AES-128, fMP4+audio → .mp4 30/30/18 dtk, frame ter-decode |
| M4 output .mp4 tanpa re-encode, tanpa ffmpeg | ✅ `AVAssetReader` → `AVAssetWriter` passthrough |
| M6 DRM ditolak (SAMPLE-AES, KEYFORMAT non-identity, video EME) | ✅ |
| M7 YouTube: deteksi, overlay, dan grab mati total | ✅ |
| Live stream | ⚠️ ditolak dengan pesan jelas (belum didukung) |

**Temuan penting**
- `AVMutableComposition.insertTimeRange` gagal (-12780) di macOS 27 bahkan untuk MP4 biasa, dan butuh timing presisi yang tak dimiliki fMP4 hasil gabungan. `AVAssetReader`/`AVAssetWriter` dengan input yang di-pump bersamaan (interleaved) bekerja untuk semua kasus — satu jalur export.
- Safari memutar HLS native: `<video>.currentSrc` = URL `.m3u8` (bukan `blob:`), jadi jenis media ditentukan dari URL, bukan dari elemen.
- Resume HLS per segmen (segmen selesai disimpan di `<id>.hoardly-hls/`).

**Belum:** DASH (M5, P2), live stream, verifikasi export di macOS 14.

## 16. M6 — Persiapan Rilis (2026-09-28)
| Item | Status |
|---|---|
| Ikon app (AppIcon 16–1024), ikon ekstensi 16–128, logo terang/gelap, aset toko | ✅ `scripts/make-icons.swift` |
| Onboarding: browser terpasang terdeteksi, status ekstensi Safari, Open at login | ✅ jendela Welcome (juga di menu "Set Up Browsers…") |
| **Pairing satu klik** (menggantikan salin token): ekstensi → `/pair` → dialog "Connect" di app → token | ✅ e2e Helium (dialog diklik otomatis); token manual tetap ada |
| Sparkle 2.10 (SPM), menu "Check for Updates…", feed `github.com/haonlabs/hoardly/releases/latest/download/appcast.xml` | ✅ terpasang; `SUPublicEDKey` dibuat oleh `scripts/release.sh keys` |
| `scripts/release.sh`: archive → Developer ID → DMG → notarize → staple → appcast | ✅ mode `--local` teruji (DMG universal 2,2 MB); mode penuh butuh akun |
| `scripts/package-extension.sh`: satu ZIP untuk Chrome/Edge/Firefox, tanpa `nativeMessaging` | ✅ |
| README, PRIVACY.md, `docs/store-listing.md` (deskripsi + justifikasi permission) | ✅ |
| Lokalisasi Bahasa Indonesia (String Catalog, 84 string) | ✅ diverifikasi via screenshot |
| Privasi: cookie dihapus dari `downloads.json` begitu unduhan selesai | ✅ diuji e2e |

**Menunggu akun (dikerjakan pemilik):** Apple Developer Program (Developer ID + notarization), Chrome Web Store / Edge Add-ons / Firefox AMO, repo publik `haonlabs/hoardly`, lalu `scripts/release.sh keys` → rilis pertama.

**Belum:** ikon menu bar kustom, lokalisasi teks ekstensi, verifikasi macOS 14.

## 17. Verifikasi (saat implementasi)
- **Unit test** (`HoardlyTests`): pembagian segmen & dynamic split, parser HLS (master/media playlist, AES-128 key), resume state encode/decode.
- **Server uji lokal** yang mendukung `Range` (mis. `caddy file-server` atau skrip kecil) + mode "tanpa Range" + mode "putus acak" → bandingkan SHA-256 hasil dengan sumber.
- **Uji resume:** `kill -9` Hoardly di tengah download 5 GB, jalankan ulang, pastikan lanjut dan hash identik.
- **Checklist manual per browser** (Safari, Chrome, Helium, Arc, Firefox): klik link .zip/.dmg, context menu, download ber-login (cookies), ⌥-klik bypass, app tidak berjalan (fallback), video mp4 & stream HLS publik.
- **Rilis:** `spctl --assess` pada app ter-notarize; instal bersih di user macOS baru.
