import Foundation

nonisolated protocol DownloadEngine: Sendable {
    func start()
    func pause()
}

nonisolated struct StreamProgress: Codable, Equatable, Sendable {
    var variant: URL? // quality picked in the New Download panel; nil = highest bandwidth
    var segments = 0
    var done = 0
    var bytes: Int64 = 0
}

/// A byte range of the file, fetched by one connection at a time.
nonisolated struct Segment: Codable, Equatable, Sendable {
    var start: Int64
    var end: Int64 // exclusive; Int64.max while the total size is unknown
    var received: Int64 = 0

    var position: Int64 { start + received }
    var remaining: Int64 { end - position }
}

nonisolated struct Download: Codable, Identifiable, Sendable {
    enum State: Codable, Equatable, Sendable {
        case queued, running, paused, completed
        case failed(String)
    }

    var id = UUID()
    var url: URL
    var headers: [String: String] = [:] // Cookie, Referer, User-Agent from the browser
    var directory: URL
    var fileName: String?
    var totalBytes: Int64?
    var validator: String? // strong ETag or Last-Modified, sent as If-Range so a changed file isn't stitched
    var acceptsRanges = false
    var segments: [Segment] = []
    var state: State = .queued
    var addedAt = Date()
    var stream: StreamProgress? // set for HLS; nil for plain files

    var received: Int64 { stream?.bytes ?? segments.reduce(0) { $0 + $1.received } }
    /// 0…1 when known: bytes for files, segments for streams.
    var fraction: Double? {
        if let stream { return stream.segments > 0 ? Double(stream.done) / Double(stream.segments) : nil }
        guard let totalBytes, totalBytes > 0 else { return nil }
        return Double(received) / Double(totalBytes)
    }
    var partURL: URL { directory.appending(path: "\(id.uuidString)" + (stream == nil ? ".hoardly-part" : ".hoardly-hls")) }
    var displayName: String { fileName ?? url.lastPathComponent }
    var category: Category { Category(fileName: displayName) }
    var fileURL: URL? { state == .completed ? directory.appending(path: displayName) : nil }
}

/// Q2: files sort into a subfolder of the download folder by extension.
nonisolated enum Category: String, CaseIterable, Codable, Sendable {
    case video = "Video", music = "Music", documents = "Documents", archives = "Archives", programs = "Programs", other = "Other"

    init(fileName: String) {
        let ext = (fileName as NSString).pathExtension.lowercased()
        self = Self.allCases.first { $0.extensions.contains(ext) } ?? .other
    }

    var extensions: Set<String> {
        switch self {
        case .video: ["mp4", "mkv", "mov", "avi", "webm", "m4v", "wmv", "flv", "ts", "3gp"]
        case .music: ["mp3", "m4a", "aac", "flac", "wav", "ogg", "opus", "aiff", "wma"]
        case .documents: ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "txt", "rtf", "epub", "csv"]
        case .archives: ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "iso"]
        case .programs: ["dmg", "pkg", "app", "exe", "msi", "apk", "deb", "rpm", "appimage"]
        case .other: []
        }
    }

    var symbol: String {
        switch self {
        case .video: "film"
        case .music: "music.note"
        case .documents: "doc.text"
        case .archives: "archivebox"
        case .programs: "app.badge"
        case .other: "doc"
        }
    }
}

nonisolated enum Segments {
    /// IDM-style dynamic segmentation: a free connection takes the back half of the segment
    /// with the most bytes left. Returns the new segment's index, or nil when nothing is worth splitting.
    static func splitLargest(_ segments: inout [Segment], minSize: Int64) -> Int? {
        guard let i = segments.indices.max(by: { segments[$0].remaining < segments[$1].remaining }) else { return nil }
        let segment = segments[i]
        guard segment.end != .max, segment.remaining >= 2 * minSize else { return nil }
        let mid = segment.position + segment.remaining / 2
        segments[i].end = mid
        segments.append(Segment(start: mid, end: segment.end))
        return segments.count - 1
    }
}

/// `Content-Range: bytes 100-199/1000` (total may be `*`).
nonisolated struct ContentRange: Equatable {
    let start: Int64
    let total: Int64?

    init?(_ header: String?) {
        guard let header, header.hasPrefix("bytes ") else { return nil }
        let parts = header.dropFirst(6).split(separator: "/")
        guard parts.count == 2, let dash = parts[0].firstIndex(of: "-"),
              let start = Int64(parts[0][..<dash]) else { return nil }
        self.start = start
        total = Int64(parts[1])
    }
}
