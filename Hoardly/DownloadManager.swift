import Foundation
import Observation

/// Owns the download list: queueing, persistence, and one SegmentedDownload per running item.
@Observable
final class DownloadManager {
    private(set) var downloads: [Download] = []
    private(set) var speeds: [UUID: Int64] = [:] // bytes per second
    var maxConcurrent = 3
    var connections = 8

    @ObservationIgnored private var engines: [UUID: SegmentedDownload] = [:]
    @ObservationIgnored private var samples: [UUID: (bytes: Int64, at: Date)] = [:]
    private let storeURL = URL.applicationSupportDirectory.appending(path: "Hoardly/downloads.json")

    var directory: URL {
        UserDefaults.standard.string(forKey: "downloadDirectory").map { URL(filePath: $0) } ?? .downloadsDirectory
    }

    init() {
        if let data = try? Data(contentsOf: storeURL),
           let saved = try? JSONDecoder().decode([Download].self, from: data) {
            // Anything running when the app died picks up where its last flush left off.
            downloads = saved.map { var d = $0; if d.state == .running { d.state = .queued }; return d }
        }
        schedule()
    }

    func add(_ url: URL, headers: [String: String] = [:]) {
        downloads.append(Download(url: url, headers: headers, directory: directory))
        save()
        schedule()
    }

    func pause(_ id: UUID) {
        if let engine = engines[id] {
            engine.pause() // the engine reports .paused back through update()
        } else if let i = index(id), downloads[i].state == .queued {
            downloads[i].state = .paused
            save()
        }
    }

    func resume(_ id: UUID) {
        guard let i = index(id) else { return }
        switch downloads[i].state {
        case .paused, .failed: downloads[i].state = .queued
        default: return
        }
        save()
        schedule()
    }

    func fileURL(_ download: Download) -> URL? {
        download.state == .completed ? download.directory.appending(path: download.displayName) : nil
    }

    private func schedule() {
        for i in downloads.indices where downloads[i].state == .queued && engines.count < maxConcurrent {
            let engine = SegmentedDownload(downloads[i], connections: connections) { [weak self] update in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.apply(update) } }
            }
            engines[downloads[i].id] = engine
            downloads[i].state = .running
            engine.start()
        }
    }

    private func apply(_ update: Download) {
        guard let i = index(update.id) else { return }
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
            schedule()
        }
        save()
    }

    private func save() { // ponytail: rewrites the whole list each second; move to SQLite if lists get huge
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(downloads).write(to: storeURL, options: .atomic)
    }

    private func index(_ id: UUID) -> Int? { downloads.firstIndex { $0.id == id } }
}
