import CoreServices
import Foundation
import os

/// Fetches one file over several HTTP range connections into `<id>.hoardly-part`, then moves it into place.
/// All mutable state is confined to `queue`, which is also the URLSession delegate queue.
nonisolated final class SegmentedDownload: NSObject, URLSessionDataDelegate, DownloadEngine, @unchecked Sendable {
    static let minSplit: Int64 = 1 << 20
    static let maxRetries = 8
    private static let log = Logger(subsystem: "id.haonlabs.hoardly", category: "engine")

    private let queue = DispatchQueue(label: "id.haonlabs.hoardly.download")
    private let connections: Int
    private let onUpdate: @Sendable (Download) -> Void
    private var download: Download
    private var limit: Int // lowered when the server says too many connections
    // Ephemeral: alt-svc stays in memory per session, so each one-task session speaks HTTP/2. A persisted
    // alt-svc cache moves CFNetwork to HTTP/3, which ran at 0.2 MB/s vs 6 MB/s over h2 on proof.ovh.net.
    private var config = URLSessionConfiguration.ephemeral
    private let delegateQueue = OperationQueue()
    // One session per task: sessions don't share connection pools, so each segment gets its own TCP
    // connection. A single session would multiplex every range over one HTTP/2 connection — no speedup.
    private var sessions: [ObjectIdentifier: URLSession] = [:]
    private var file: FileHandle?
    private var timer: DispatchSourceTimer?
    private var active = false
    private var tasks: [ObjectIdentifier: Int] = [:] // task → segment index
    private var retrying: Set<Int> = []
    private var throttled: Set<ObjectIdentifier> = []
    private var failures: [Int: Int] = [:]
    private var retryAfter: [Int: TimeInterval] = [:]

    init(_ download: Download, connections: Int, onUpdate: @escaping @Sendable (Download) -> Void) {
        self.download = download
        self.connections = connections
        self.limit = connections
        self.onUpdate = onUpdate
    }

    func start() { queue.async { self.begin() } }
    func pause() { queue.async { if self.active { self.stop(.paused) } } }

    // MARK: - Lifecycle

    private func begin() {
        do {
            try FileManager.default.createDirectory(at: download.directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: download.partURL.path) {
                FileManager.default.createFile(atPath: download.partURL.path, contents: nil)
                download.segments = []
            }
            file = try FileHandle(forWritingTo: download.partURL)
            if download.segments.isEmpty || !download.acceptsRanges {
                // Fresh start, or a server without range support: (re)fetch from byte 0.
                // The first response tells us the size and whether ranges work.
                try file?.truncate(atOffset: 0)
                download.segments = [Segment(start: 0, end: .max)]
                download.acceptsRanges = false
            }
        } catch {
            return stop(.failed(error.localizedDescription))
        }

        delegateQueue.underlyingQueue = queue
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 30
        config.urlCache = nil

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.flush() }
        timer.resume()
        self.timer = timer

        active = true
        download.state = .running
        onUpdate(download)
        fill()
    }

    /// Persist point: bytes are on disk before the snapshot claiming them leaves this object.
    private func flush() {
        guard active else { return }
        try? file?.synchronize()
        onUpdate(download)
    }

    private func stop(_ state: Download.State) {
        active = false
        sessions.values.forEach { $0.invalidateAndCancel() }
        sessions.removeAll()
        timer?.cancel()
        timer = nil
        tasks.removeAll()
        retrying.removeAll()
        try? file?.synchronize()
        try? file?.close()
        file = nil
        download.state = state
        onUpdate(download)
    }

    private func finish() {
        active = false
        timer?.cancel()
        timer = nil
        do {
            try file?.synchronize()
            try file?.close()
            file = nil
            let size = try FileManager.default.attributesOfItem(atPath: download.partURL.path)[.size] as? Int64
            if let total = download.totalBytes, size != total {
                throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "Expected \(total) bytes, got \(size ?? 0)"])
            }
            let destination = Self.unusedURL(download.directory.appending(path: Self.safeName(download.displayName)))
            try FileManager.default.moveItem(at: download.partURL, to: destination)
            download.fileName = destination.lastPathComponent
            Self.markDownloaded(destination, from: download)
            download.state = .completed
        } catch {
            download.state = .failed(error.localizedDescription)
        }
        onUpdate(download)
    }

    // MARK: - Connections

    private func fill() {
        if limit < connections { coalesce() }
        while active, tasks.count < (download.acceptsRanges ? limit : 1) {
            let busy = Set(tasks.values).union(retrying)
            if let idle = download.segments.indices.first(where: { download.segments[$0].remaining > 0 && !busy.contains($0) }) {
                launch(idle)
            } else if download.acceptsRanges, download.totalBytes != nil, limit == connections, // throttled: no new requests
                      let new = Segments.splitLargest(&download.segments, minSize: Self.minSplit) {
                launch(new)
            } else {
                break
            }
        }
        if active, tasks.isEmpty, retrying.isEmpty, download.segments.allSatisfy({ $0.remaining <= 0 }) {
            finish()
        }
    }

    /// Under a server's connection limit every new request costs a slot (and may earn a 429), so fold
    /// untouched segments back into the running stream that ends where they start.
    private func coalesce() {
        let running = Set(tasks.values)
        let busy = running.union(retrying)
        for stream in running {
            while let next = download.segments.indices.first(where: {
                !busy.contains($0) && download.segments[$0].received == 0 && download.segments[$0].remaining > 0
                    && download.segments[$0].start == download.segments[stream].end
            }) {
                download.segments[stream].end = download.segments[next].end
                download.segments[next].end = download.segments[next].start
            }
        }
    }

    private func launch(_ index: Int) {
        let segment = download.segments[index]
        var request = URLRequest(url: download.url)
        for (field, value) in download.headers { request.setValue(value, forHTTPHeaderField: field) }
        // Open-ended so the stream can keep going if later segments get folded into it; we cut it at `end`.
        request.setValue("bytes=\(segment.position)-", forHTTPHeaderField: "Range")
        if segment.position > 0, let validator = download.validator {
            request.setValue(validator, forHTTPHeaderField: "If-Range")
        }
        let session = URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)
        let task = session.dataTask(with: request)
        tasks[ObjectIdentifier(task)] = index
        sessions[ObjectIdentifier(task)] = session
        task.resume()
    }

    private func retry(_ index: Int, _ error: Error?) {
        let attempt = failures[index, default: 0] + 1
        failures[index] = attempt
        guard attempt <= Self.maxRetries else {
            return stop(.failed(error?.localizedDescription ?? "The server kept dropping the connection"))
        }
        if !download.acceptsRanges { // can't resume mid-file; start over
            download.segments[index].received = 0
            try? file?.truncate(atOffset: 0)
        }
        retrying.insert(index)
        let delay = retryAfter.removeValue(forKey: index) ?? min(30, pow(2, Double(attempt - 1)))
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.active else { return }
            self.retrying.remove(index)
            self.fill() // relaunches through the connection limit
        }
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard active, let index = tasks[ObjectIdentifier(dataTask)], let http = response as? HTTPURLResponse else {
            return completionHandler(.cancel)
        }
        let segment = download.segments[index]
        Self.log.debug("segment \(index) @\(segment.position): HTTP \(http.statusCode), \(self.tasks.count) running, limit \(self.limit)")
        switch http.statusCode {
        case 206:
            guard let range = ContentRange(http.value(forHTTPHeaderField: "Content-Range")), range.start == segment.position else {
                stop(.failed("The server sent an unexpected byte range"))
                return completionHandler(.cancel)
            }
            if !download.acceptsRanges {
                download.acceptsRanges = true
                adopt(http, total: range.total)
            } else if range.total != download.totalBytes {
                stop(.failed("The file changed on the server. Restart the download."))
                return completionHandler(.cancel)
            }
        case 200 where segment.position == 0 && download.segments.count == 1:
            adopt(http, total: http.expectedContentLength > 0 ? http.expectedContentLength : nil)
        case 200:
            stop(.failed("The file changed on the server. Restart the download."))
            return completionHandler(.cancel)
        case 429, 503:
            limit = max(1, min(limit, tasks.count) - 1) // server caps connections per client; stay under it
            retryAfter[index] = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throttled.insert(ObjectIdentifier(dataTask))
            return completionHandler(.cancel)
        case 408, 500...599:
            return completionHandler(.cancel)
        default:
            stop(.failed("Server replied HTTP \(http.statusCode)"))
            return completionHandler(.cancel)
        }
        completionHandler(.allow)
        fill()
    }

    /// First response: learn size, validator and file name.
    private func adopt(_ http: HTTPURLResponse, total: Int64?) {
        download.totalBytes = total
        if let total { download.segments[0].end = total }
        let etag = http.value(forHTTPHeaderField: "ETag").flatMap { $0.hasPrefix("W/") ? nil : $0 }
        download.validator = etag ?? http.value(forHTTPHeaderField: "Last-Modified")
        if download.fileName == nil { download.fileName = http.suggestedFilename }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard active, let index = tasks[ObjectIdentifier(dataTask)] else { return }
        let segment = download.segments[index]
        let chunk = data.prefix(Int(min(Int64(data.count), segment.remaining)))
        do {
            try file?.seek(toOffset: UInt64(segment.position))
            try file?.write(contentsOf: chunk)
        } catch {
            return stop(.failed(error.localizedDescription))
        }
        download.segments[index].received += Int64(chunk.count)
        failures[index] = 0
        if download.segments[index].remaining <= 0 { dataTask.cancel() } // reached a split point
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        sessions.removeValue(forKey: ObjectIdentifier(task))?.finishTasksAndInvalidate()
        guard active, let index = tasks.removeValue(forKey: ObjectIdentifier(task)) else { return }
        if download.segments[index].end == .max, error == nil { // unknown size: end of stream is end of file
            download.segments[index].end = download.segments[index].position
            download.totalBytes = download.segments[index].end
        }
        let wasThrottled = throttled.remove(ObjectIdentifier(task)) != nil
        Self.log.debug("segment \(index) ended, \(self.download.segments[index].remaining) left, error: \(String(describing: error))")
        if download.segments[index].remaining > 0 {
            if wasThrottled, !tasks.isEmpty {
                // Other connections still run; the segment just waits for a free slot.
            } else if Self.isTransient(error) {
                retry(index, error)
            } else {
                return stop(.failed(error?.localizedDescription ?? "Download failed"))
            }
        }
        fill()
    }

    /// Worth retrying: short body (nil), our own cancel after a 5xx, or a network hiccup. Not ATS, TLS, bad URL…
    static func isTransient(_ error: Error?) -> Bool {
        guard let error else { return true }
        let transient: [URLError.Code] = [.cancelled, .timedOut, .networkConnectionLost, .notConnectedToInternet,
                                          .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed]
        return (error as? URLError).map { transient.contains($0.code) } ?? false
    }

    // MARK: - Files

    /// Keeps only the last path component so a hostile Content-Disposition can't escape the folder.
    static func safeName(_ name: String) -> String {
        let last = (name.replacingOccurrences(of: ":", with: "-") as NSString).lastPathComponent
        return ["", ".", ".."].contains(last) ? "download" : last
    }

    /// `file.zip` → `file (2).zip` when taken.
    static func unusedURL(_ url: URL) -> URL {
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var candidate = url
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            candidate = url.deletingLastPathComponent().appending(path: name)
            n += 1
        }
        return candidate
    }

    /// Quarantine so Gatekeeper still checks the file, plus "Where from" shown in Finder's Get Info.
    static func markDownloaded(_ url: URL, from download: Download) {
        let referer = download.headers["Referer"].flatMap(URL.init(string:))
        var quarantine: [String: Any] = [
            kLSQuarantineAgentNameKey as String: "Hoardly",
            kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload as String,
            kLSQuarantineDataURLKey as String: download.url,
        ]
        quarantine[kLSQuarantineOriginURLKey as String] = referer
        var values = URLResourceValues()
        values.quarantineProperties = quarantine
        var url = url
        try? url.setResourceValues(values)

        let froms = [download.url.absoluteString] + (referer.map { [$0.absoluteString] } ?? [])
        if let plist = try? PropertyListSerialization.data(fromPropertyList: froms, format: .binary, options: 0) {
            _ = plist.withUnsafeBytes {
                setxattr(url.path, "com.apple.metadata:kMDItemWhereFroms", $0.baseAddress, plist.count, 0, 0)
            }
        }
    }
}
