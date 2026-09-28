import AVFoundation
import CommonCrypto
import Foundation

/// M3/M6: just enough of RFC 8216 to download VOD streams — master/media playlists, AES-128, fMP4 maps, byte ranges.
nonisolated enum HLS {
    struct Variant: Equatable, Sendable {
        let url: URL
        let bandwidth: Int
        let resolution: String?
        let audioGroup: String?
    }

    struct Rendition: Equatable, Sendable {
        let group: String
        let url: URL
        let isDefault: Bool
    }

    struct Key: Equatable, Sendable {
        let url: URL
        let iv: Data?
    }

    struct Part: Equatable, Sendable {
        let url: URL
        let range: ClosedRange<Int64>?
        var key: Key?
        var sequence = 0
    }

    struct Media: Equatable, Sendable {
        var map: Part?
        var segments: [Part] = []
        var isLive = true
    }

    enum Playlist: Equatable, Sendable {
        case master([Variant], audio: [Rendition])
        case media(Media)
    }

    enum Failure: LocalizedError {
        case notPlaylist, drm, live
        var errorDescription: String? {
            switch self {
            case .notPlaylist: "Not an HLS playlist"
            case .drm: "This stream is DRM-protected and can't be downloaded"
            case .live: "Live streams aren't supported yet"
            }
        }
    }

    static func parse(_ text: String, base: URL) throws -> Playlist {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.first == "#EXTM3U" else { throw Failure.notPlaylist }
        var variants: [Variant] = [], audio: [Rendition] = [], media = Media()
        var pendingVariant: [String: String]?, pendingRange: ClosedRange<Int64>?, key: Key?
        var sequence = 0, lastRangeEnd: Int64 = 0, sawSegment = false

        for line in lines.dropFirst() where !line.isEmpty {
            let pieces = line.split(separator: ":", maxSplits: 1).map(String.init)
            let (tag, value) = (pieces[0], pieces.count > 1 ? pieces[1] : "")
            switch tag {
            case "#EXT-X-STREAM-INF":
                pendingVariant = attributes(value)
            case "#EXT-X-MEDIA":
                let a = attributes(value)
                if a["TYPE"] == "AUDIO", let uri = a["URI"], let url = URL(string: uri, relativeTo: base) {
                    audio.append(Rendition(group: a["GROUP-ID"] ?? "", url: url.absoluteURL, isDefault: a["DEFAULT"] == "YES"))
                }
            case "#EXT-X-KEY", "#EXT-X-SESSION-KEY":
                let a = attributes(value)
                switch a["METHOD"] {
                case "NONE": key = nil
                case "AES-128" where (a["KEYFORMAT"] ?? "identity") == "identity":
                    guard let uri = a["URI"], let url = URL(string: uri, relativeTo: base) else { throw Failure.notPlaylist }
                    key = Key(url: url.absoluteURL, iv: a["IV"].flatMap(hexData))
                default: throw Failure.drm // SAMPLE-AES, FairPlay/Widevine key formats
                }
            case "#EXT-X-MAP":
                let a = attributes(value)
                if let uri = a["URI"], let url = URL(string: uri, relativeTo: base) {
                    media.map = Part(url: url.absoluteURL, range: a["BYTERANGE"].flatMap { byteRange($0, after: 0) })
                }
            case "#EXT-X-MEDIA-SEQUENCE":
                sequence = Int(value) ?? 0
            case "#EXT-X-BYTERANGE":
                pendingRange = byteRange(value, after: lastRangeEnd)
            case "#EXT-X-ENDLIST":
                media.isLive = false
            case "#EXT-X-PLAYLIST-TYPE" where value == "VOD":
                media.isLive = false
            case "#EXTINF":
                sawSegment = true
            default:
                guard !line.hasPrefix("#"), let url = URL(string: line, relativeTo: base)?.absoluteURL else { continue }
                if let a = pendingVariant {
                    variants.append(Variant(url: url, bandwidth: Int(a["BANDWIDTH"] ?? "") ?? 0,
                                            resolution: a["RESOLUTION"], audioGroup: a["AUDIO"]))
                    pendingVariant = nil
                } else {
                    media.segments.append(Part(url: url, range: pendingRange, key: key, sequence: sequence))
                    lastRangeEnd = (pendingRange?.upperBound ?? -1) + 1
                    pendingRange = nil
                    sequence += 1
                }
            }
        }
        if !variants.isEmpty { return .master(variants, audio: audio) }
        guard sawSegment else { throw Failure.notPlaylist }
        return .media(media)
    }

    /// `KEY=value,KEY="quoted, value"`
    static func attributes(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for match in text.matches(of: /([A-Z0-9-]+)=("[^"]*"|[^,]*)/) {
            result[String(match.1)] = String(match.2).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return result
    }

    /// `length[@offset]`; without an offset the range continues from the previous one.
    static func byteRange(_ text: String, after previousEnd: Int64) -> ClosedRange<Int64>? {
        let parts = text.split(separator: "@").compactMap { Int64($0) }
        guard let length = parts.first, length > 0 else { return nil }
        let start = parts.count > 1 ? parts[1] : previousEnd
        return start...(start + length - 1)
    }

    static func hexData(_ text: String) -> Data? {
        var hex = text.lowercased().replacingOccurrences(of: "0x", with: "")
        if hex.count % 2 == 1 { hex = "0" + hex }
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }

    /// Without an explicit IV, AES-128 uses the segment's media sequence number, big-endian, as the IV.
    static func iv(for part: Part) -> Data {
        part.key?.iv ?? Data(repeating: 0, count: 8) + withUnsafeBytes(of: UInt64(part.sequence).bigEndian) { Data($0) }
    }

    static func decrypt(_ data: Data, key: Data, iv: Data) throws -> Data {
        var out = Data(count: data.count + kCCBlockSizeAES128)
        var written = 0
        let status = out.withUnsafeMutableBytes { outPtr in
            data.withUnsafeBytes { inPtr in
                key.withUnsafeBytes { keyPtr in
                    iv.withUnsafeBytes { ivPtr in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                                keyPtr.baseAddress, key.count, ivPtr.baseAddress, inPtr.baseAddress, data.count,
                                outPtr.baseAddress, outPtr.count, &written)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw CocoaError(.fileReadCorruptFile) }
        return out.prefix(written)
    }

    /// M4: copy samples into one .mp4 without re-encoding — MPEG-TS remuxed, fMP4 rewrapped, separate audio muxed in.
    /// AVAssetReader → AVAssetWriter rather than AVMutableComposition: composition inserts fail (-12780) on macOS 27
    /// even for plain MP4s, and need precise timing that concatenated fMP4 can't provide.
    static func export(video: URL, audio: URL?, to output: URL) async throws {
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        var readers: [AVAssetReader] = []
        var pumps: [(AVAssetReaderTrackOutput, AVAssetWriterInput)] = []
        let sources = [(video, [AVMediaType.video, .audio])] + (audio.map { [($0, [AVMediaType.audio])] } ?? [])
        for (url, types) in sources {
            let asset = AVURLAsset(url: url)
            let reader = try AVAssetReader(asset: asset)
            for track in try await asset.load(.tracks) where types.contains(track.mediaType) {
                let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
                let input = AVAssetWriterInput(mediaType: track.mediaType, outputSettings: nil,
                                               sourceFormatHint: try await track.load(.formatDescriptions).first)
                reader.add(output)
                writer.add(input)
                pumps.append((output, input))
            }
            readers.append(reader)
        }
        guard !pumps.isEmpty else { throw HLS.Failure.notPlaylist }
        readers.forEach { $0.startReading() }
        // Stream segments rarely start at t=0; begin the file at the earliest sample.
        let firsts = pumps.map { $0.0.copyNextSampleBuffer() }
        let start = firsts.compactMap { $0.map(CMSampleBufferGetPresentationTimeStamp) }.min() ?? .zero
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: start)

        // Each input pulls on its own queue so the writer can interleave audio and video.
        await withTaskGroup(of: Void.self) { group in
            for (index, (output, input)) in pumps.enumerated() {
                nonisolated(unsafe) let (output, input, first) = (output, input, firsts[index])
                group.addTask {
                    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                        nonisolated(unsafe) var pending = first
                        input.requestMediaDataWhenReady(on: DispatchQueue(label: "id.haonlabs.hoardly.mux")) {
                            while input.isReadyForMoreMediaData {
                                guard let sample = pending ?? output.copyNextSampleBuffer() else {
                                    input.markAsFinished()
                                    return done.resume()
                                }
                                pending = nil
                                input.append(sample)
                            }
                        }
                    }
                }
            }
        }
        await writer.finishWriting()
        if let failed = readers.first(where: { $0.status == .failed }) { throw failed.error ?? CocoaError(.fileReadCorruptFile) }
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }
}

/// Downloads a VOD HLS stream: segments in parallel into `<id>.hoardly-hls/`, then one .mp4.
/// Finished segments stay on disk, so pause/crash resumes at segment granularity.
actor HLSDownload: DownloadEngine {
    private var download: Download
    private let connections: Int
    private let onUpdate: @Sendable (Download) -> Void
    private var task: Task<Void, Never>?
    private var keys: [URL: Data] = [:]
    private var lastReport = Date.distantPast

    init(_ download: Download, connections: Int, onUpdate: @escaping @Sendable (Download) -> Void) {
        self.download = download
        self.connections = connections
        self.onUpdate = onUpdate
    }

    nonisolated func start() { Task { await begin() } }
    nonisolated func pause() { Task { await cancel() } }

    private func begin() {
        task = Task { await run() }
    }

    private func cancel() {
        task?.cancel()
    }

    private func run() async {
        download.state = .running
        onUpdate(download)
        do {
            let work = download.partURL
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let (video, audio) = try await playlists()
            let all = video.segments.count + (audio?.segments.count ?? 0)
            download.stream?.segments = all
            let videoFile = try await fetch(video, prefix: "v", into: work)
            var audioFile: URL?
            if let audio { audioFile = try await fetch(audio, prefix: "a", into: work) }
            try Task.checkCancellation()

            let name = SegmentedDownload.safeName(download.displayName)
            let output = SegmentedDownload.unusedURL(download.directory.appending(path: name))
            try await HLS.export(video: videoFile, audio: audioFile, to: output)
            try? FileManager.default.removeItem(at: work)
            SegmentedDownload.markDownloaded(output, from: download)
            download.fileName = output.lastPathComponent
            download.state = .completed
        } catch is CancellationError {
            download.state = .paused
        } catch let error as URLError where error.code == .cancelled {
            download.state = .paused
        } catch {
            download.state = .failed(error.localizedDescription)
        }
        onUpdate(download)
    }

    /// Media playlist for the chosen (or best) variant, plus its separate audio rendition if it has one.
    private func playlists() async throws -> (HLS.Media, HLS.Media?) {
        switch try await playlist(download.url) {
        case .media(let media):
            guard !media.isLive else { throw HLS.Failure.live }
            return (media, nil)
        case .master(let variants, let renditions):
            guard let variant = variants.first(where: { $0.url == download.stream?.variant })
                ?? variants.max(by: { $0.bandwidth < $1.bandwidth }) else { throw HLS.Failure.notPlaylist }
            guard case .media(let video) = try await playlist(variant.url) else { throw HLS.Failure.notPlaylist }
            guard !video.isLive else { throw HLS.Failure.live }
            let group = renditions.filter { $0.group == variant.audioGroup }
            guard let rendition = group.first(where: \.isDefault) ?? group.first,
                  case .media(let audio) = try await playlist(rendition.url) else { return (video, nil) }
            return (video, audio)
        }
    }

    private func playlist(_ url: URL) async throws -> HLS.Playlist {
        let data = try await get(url, range: nil)
        return try HLS.parse(String(decoding: data, as: UTF8.self), base: url)
    }

    /// All segments of one playlist, `connections` at a time, concatenated into a single file.
    private func fetch(_ media: HLS.Media, prefix: String, into work: URL) async throws -> URL {
        let file: @Sendable (Int) -> URL = { work.appending(path: "\(prefix)\(String(format: "%06d", $0))") }
        let parts = (media.map.map { [$0] } ?? []) + media.segments // init section first
        let offset = media.map == nil ? 0 : 1

        try await withThrowingTaskGroup(of: Int64?.self) { group in
            var next = 0
            func enqueue() {
                guard next < parts.count else { return }
                let (i, part, destination) = (next, parts[next], file(next))
                next += 1
                group.addTask {
                    if FileManager.default.fileExists(atPath: destination.path) { // resumed: done earlier
                        let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int) ?? 0
                        return i < offset ? nil : Int64(size)
                    }
                    var data = try await self.get(part.url, range: part.range)
                    if let key = part.key {
                        data = try HLS.decrypt(data, key: try await self.key(key.url), iv: HLS.iv(for: part))
                    }
                    let temp = destination.appendingPathExtension("tmp")
                    try data.write(to: temp)
                    try FileManager.default.moveItem(at: temp, to: destination) // only whole segments count on resume
                    return i < offset ? nil : Int64(data.count) // nil: the init section isn't a counted segment
                }
            }
            for _ in 0..<connections { enqueue() }
            while let result = try await group.next() {
                if let bytes = result { progressed(bytes) }
                enqueue()
            }
        }

        let ext = media.map != nil ? "mp4" : (media.segments.first?.url.pathExtension.lowercased() == "aac" ? "aac" : "ts")
        let joined = work.appending(path: "\(prefix).\(ext)")
        FileManager.default.createFile(atPath: joined.path, contents: nil)
        let handle = try FileHandle(forWritingTo: joined)
        defer { try? handle.close() }
        for i in parts.indices {
            try handle.write(contentsOf: Data(contentsOf: file(i)))
        }
        return joined
    }

    private func progressed(_ bytes: Int64) {
        download.stream?.done += 1
        download.stream?.bytes += bytes
        if Date().timeIntervalSince(lastReport) > 0.5 {
            lastReport = Date()
            onUpdate(download)
        }
    }

    private func key(_ url: URL) async throws -> Data {
        if let key = keys[url] { return key }
        let key = try await get(url, range: nil)
        keys[url] = key
        return key
    }

    /// One ephemeral session per request, for the same reason as SegmentedDownload: no alt-svc cache, no HTTP/3.
    private func get(_ url: URL, range: ClosedRange<Int64>?) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 30)
        for (field, value) in download.headers { request.setValue(value, forHTTPHeaderField: field) }
        if let range { request.setValue("bytes=\(range.lowerBound)-\(range.upperBound)", forHTTPHeaderField: "Range") }
        for attempt in 1...4 {
            let session = URLSession(configuration: .ephemeral)
            defer { session.finishTasksAndInvalidate() }
            do {
                let (data, response) = try await session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if (200..<300).contains(status) { return data }
                if status < 500, status != 429 { throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Server replied HTTP \(status) for \(url.lastPathComponent)"]) }
            } catch let error as URLError where SegmentedDownload.isTransient(error) && error.code != .cancelled && attempt < 4 {
                // retry below
            }
            try await Task.sleep(for: .seconds(Double(attempt * attempt)))
        }
        throw URLError(.networkConnectionLost)
    }
}
