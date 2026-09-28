// swift scripts/probe-media.swift FILE → "duration=<s> tracks=<types> frame=<ok|none>"
import AVFoundation
let asset = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
let duration = try await asset.load(.duration).seconds
let tracks = try await asset.load(.tracks).map { $0.mediaType.rawValue }.sorted()
let generator = AVAssetImageGenerator(asset: asset)
let frame = (try? await generator.image(at: CMTime(seconds: duration / 2, preferredTimescale: 600))) != nil
print(String(format: "duration=%.0f tracks=%@ frame=%@", duration, tracks.joined(separator: ","), frame ? "ok" : "none"))
