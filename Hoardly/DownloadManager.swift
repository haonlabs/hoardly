import AppKit
import Foundation
import Observation

/// Owns the download list: queueing, persistence, and one SegmentedDownload per running item.
@Observable
final class DownloadManager {
    private(set) var downloads: [Download] = []
    private(set) var speeds: [UUID: Int64] = [:] // bytes per second
    var totalSpeed: Int64 { speeds.values.reduce(0, +) }

    @ObservationIgnored private var engines: [UUID: any DownloadEngine] = [:]
    @ObservationIgnored private var samples: [UUID: (bytes: Int64, at: Date)] = [:]
    private let storeURL = URL.applicationSupportDirectory.appending(path: "Hoardly/downloads.json")

    /// Hosted unit tests launch the app; they must not resume the user's real queue.
    static let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    static let defaults: [String: Any] = [
        "downloadDirectory": URL.downloadsDirectory.path,
        "organizeByCategory": true,
        "maxConcurrent": 3,
        "connections": 8,
        "confirmBrowserDownloads": true,
        "interceptExtensions": "zip rar 7z tar gz tgz bz2 xz iso dmg pkg exe msi apk deb rpm appimage mp4 mkv mov avi webm m4v wmv flv mp3 m4a flac wav aac ogg",
        "interceptMinSizeMB": 0,
    ]

    /// Where a new file goes: the download folder, plus its category subfolder when organizing (Q2).
    static func directory(for fileName: String) -> URL {
        let base = URL(filePath: UserDefaults.standard.string(forKey: "downloadDirectory") ?? URL.downloadsDirectory.path)
        let category = Category(fileName: fileName)
        guard UserDefaults.standard.bool(forKey: "organizeByCategory"), category != .other else { return base }
        return base.appending(path: category.rawValue)
    }

    init() {
        UserDefaults.standard.register(defaults: Self.defaults)
        guard !Self.isTesting else { return }
        if let data = try? Data(contentsOf: storeURL),
           let saved = try? JSONDecoder().decode([Download].self, from: data) {
            // Anything running when the app died picks up where its last flush left off.
            downloads = saved.map { var d = $0; if d.state == .running { d.state = .queued }; return d }
        }
        schedule()
    }

    static func isStream(_ url: URL) -> Bool { url.pathExtension.lowercased() == "m3u8" }

    func add(_ url: URL, headers: [String: String] = [:], fileName: String? = nil, directory: URL? = nil,
             start: Bool = true, stream: Bool = false, variant: URL? = nil) {
        let stream = stream || Self.isStream(url)
        var name = fileName ?? url.lastPathComponent
        if stream { name = (name as NSString).deletingPathExtension + ".mp4" } // playlists become one .mp4
        var download = Download(url: url, headers: headers, directory: directory ?? Self.directory(for: name),
                                fileName: stream ? name : fileName, state: start ? .queued : .paused)
        if stream { download.stream = StreamProgress(variant: variant) }
        downloads.append(download)
        save()
        schedule()
    }

    func pause(_ ids: Set<UUID>) {
        for id in ids {
            if let engine = engines[id] {
                engine.pause() // the engine reports .paused back through apply()
            } else if let i = index(id), downloads[i].state == .queued {
                downloads[i].state = .paused
            }
        }
        save()
    }

    func resume(_ ids: Set<UUID>) {
        for id in ids {
            guard let i = index(id) else { continue }
            switch downloads[i].state {
            case .paused, .failed: downloads[i].state = .queued
            default: break
            }
        }
        save()
        schedule()
    }

    /// Unfinished downloads always lose their partial file; `trashFiles` also trashes finished ones.
    func remove(_ ids: Set<UUID>, trashFiles: Bool) {
        for id in ids {
            guard let i = index(id) else { continue }
            let download = downloads.remove(at: i)
            engines.removeValue(forKey: id)?.pause()
            speeds[id] = nil
            samples[id] = nil
            if let file = download.fileURL {
                if trashFiles { try? FileManager.default.trashItem(at: file, resultingItemURL: nil) }
            } else {
                try? FileManager.default.removeItem(at: download.partURL)
            }
        }
        save()
        schedule()
        DockProgress.update(downloads)
    }

    private func schedule() {
        let limit = max(1, UserDefaults.standard.integer(forKey: "maxConcurrent"))
        let connections = max(1, UserDefaults.standard.integer(forKey: "connections"))
        for i in downloads.indices where downloads[i].state == .queued && engines.count < limit {
            let report: @Sendable (Download) -> Void = { [weak self] update in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.apply(update) } }
            }
            let engine: any DownloadEngine = downloads[i].stream == nil
                ? SegmentedDownload(downloads[i], connections: connections, onUpdate: report)
                : HLSDownload(downloads[i], connections: connections, onUpdate: report)
            engines[downloads[i].id] = engine
            downloads[i].state = .running
            engine.start()
        }
    }

    private func apply(_ update: Download) {
        guard let i = index(update.id), engines[update.id] != nil else { return } // removed meanwhile
        let previous = downloads[i].state
        downloads[i] = update
        let now = Date()
        if let last = samples[update.id], now > last.at {
            speeds[update.id] = Int64(Double(update.received - last.bytes) / now.timeIntervalSince(last.at))
        }
        samples[update.id] = (update.received, now)
        if update.state != .running {
            engines[update.id] = nil
            samples[update.id] = nil
            speeds[update.id] = nil
            if previous == .running, update.state != .paused { Notifier.notify(update) }
            schedule()
        }
        save()
        DockProgress.update(downloads)
    }

    private func save() { // ponytail: rewrites the whole list each second; move to SQLite if lists get huge
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(downloads).write(to: storeURL, options: .atomic)
    }

    private func index(_ id: UUID) -> Int? { downloads.firstIndex { $0.id == id } }
}
