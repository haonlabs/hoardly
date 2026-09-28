import CommonCrypto
import Foundation
import Testing
@testable import Hoardly

struct HLSTests {
    let base = URL(string: "https://cdn.example/show/master.m3u8")!

    @Test func parsesMasterWithSeparateAudio() throws {
        let text = """
        #EXTM3U
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud1",NAME="English, US",DEFAULT=YES,URI="a1/index.m3u8"
        #EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360,CODECS="avc1.4d401e,mp4a.40.2",AUDIO="aud1"
        low/index.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080,AUDIO="aud1"
        https://other.example/hi.m3u8
        """
        guard case .master(let variants, let audio) = try HLS.parse(text, base: base) else { Issue.record("not master"); return }
        #expect(variants.map(\.bandwidth) == [800_000, 5_000_000])
        #expect(variants[0].url.absoluteString == "https://cdn.example/show/low/index.m3u8")
        #expect(variants[1].url.absoluteString == "https://other.example/hi.m3u8")
        #expect(variants[0].resolution == "640x360" && variants[0].audioGroup == "aud1")
        #expect(audio == [HLS.Rendition(group: "aud1", url: URL(string: "https://cdn.example/show/a1/index.m3u8")!, isDefault: true)])
    }

    @Test func parsesMediaWithKeysMapAndByteRanges() throws {
        let text = """
        #EXTM3U
        #EXT-X-MEDIA-SEQUENCE:7
        #EXT-X-MAP:URI="main.mp4",BYTERANGE="719@0"
        #EXT-X-KEY:METHOD=AES-128,URI="k.bin",IV=0x0000000000000000000000000000000A
        #EXTINF:6,
        #EXT-X-BYTERANGE:100@719
        main.mp4
        #EXT-X-KEY:METHOD=AES-128,URI="k.bin"
        #EXTINF:6,
        #EXT-X-BYTERANGE:50
        main.mp4
        #EXT-X-KEY:METHOD=NONE
        #EXTINF:6,
        clear.m4s
        #EXT-X-ENDLIST
        """
        guard case .media(let media) = try HLS.parse(text, base: base) else { Issue.record("not media"); return }
        #expect(!media.isLive)
        #expect(media.map?.range == 0...718)
        #expect(media.segments.map(\.range) == [719...818, 819...868, nil])
        #expect(media.segments.map(\.sequence) == [7, 8, 9])
        #expect(HLS.iv(for: media.segments[0]).last == 0x0A)
        #expect(HLS.iv(for: media.segments[1]) == Data(repeating: 0, count: 15) + [8]) // sequence number as IV
        #expect(media.segments[2].key == nil)
    }

    @Test func refusesDRMAndSpotsLive() throws {
        let drm = "#EXTM3U\n#EXT-X-KEY:METHOD=SAMPLE-AES,URI=\"skd://k\",KEYFORMAT=\"com.apple.streamingkeydelivery\"\n#EXTINF:6,\na.ts"
        #expect(throws: HLS.Failure.drm) { try HLS.parse(drm, base: base) }
        let widevine = "#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"data:x\",KEYFORMAT=\"urn:uuid:edef8ba9\"\n#EXTINF:6,\na.ts"
        #expect(throws: HLS.Failure.drm) { try HLS.parse(widevine, base: base) }
        guard case .media(let live) = try HLS.parse("#EXTM3U\n#EXTINF:6,\na.ts", base: base) else { return }
        #expect(live.isLive)
        #expect(throws: HLS.Failure.notPlaylist) { try HLS.parse("<html>", base: base) }
    }

    @Test func decryptsAES128() throws {
        let key = Data((0..<16).map(UInt8.init)), iv = Data(repeating: 7, count: 16)
        let plain = Data("hello hoardly segment".utf8)
        var encrypted = Data(count: plain.count + 16), written = 0
        _ = encrypted.withUnsafeMutableBytes { out in plain.withUnsafeBytes { input in key.withUnsafeBytes { k in iv.withUnsafeBytes { v in
            CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                    k.baseAddress, 16, v.baseAddress, input.baseAddress, plain.count, out.baseAddress, out.count, &written)
        } } } }
        #expect(try HLS.decrypt(encrypted.prefix(written), key: key, iv: iv) == plain)
    }
}
