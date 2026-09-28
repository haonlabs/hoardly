import Foundation
import Testing
@testable import Hoardly

struct DownloadTests {
    @Test func splitsBackHalfOfLargestRemainingSegment() throws {
        let mb: Int64 = 1 << 20
        var segments = [Segment(start: 0, end: 100 * mb, received: 20 * mb), Segment(start: 100 * mb, end: 110 * mb)]
        let new = try #require(Segments.splitLargest(&segments, minSize: mb))
        #expect(segments[0] == Segment(start: 0, end: 60 * mb, received: 20 * mb))
        #expect(segments[new] == Segment(start: 60 * mb, end: 100 * mb))
        // Nothing covers a byte twice, nothing is lost.
        #expect(segments.map(\.end).max() == 110 * mb && segments.reduce(0) { $0 + ($1.end - $1.start) } == 110 * mb)
    }

    @Test func refusesTinyOrUnknownSizeSplits() {
        var small = [Segment(start: 0, end: 1_000, received: 10)]
        #expect(Segments.splitLargest(&small, minSize: 1 << 20) == nil)
        var unknown = [Segment(start: 0, end: .max)]
        #expect(Segments.splitLargest(&unknown, minSize: 1) == nil)
    }

    @Test func parsesContentRange() {
        #expect(ContentRange("bytes 100-199/1000") == ContentRange(start: 100, total: 1_000))
        #expect(ContentRange("bytes 0-99/*")?.total == nil)
        #expect(ContentRange("items 0-1/2") == nil)
        #expect(ContentRange(nil) == nil)
    }

    @Test func sanitizesServerFileNames() {
        #expect(SegmentedDownload.safeName("../../.zshrc") == ".zshrc")
        #expect(SegmentedDownload.safeName("a/b/setup.dmg") == "setup.dmg")
        #expect(SegmentedDownload.safeName("..") == "download")
    }
}

private extension ContentRange {
    init(start: Int64, total: Int64?) {
        self.init("bytes \(start)-\(start)/\(total.map(String.init) ?? "*")")!
    }
}

struct CategoryTests {
    @Test func categorizesByExtension() {
        #expect(Category(fileName: "Movie.MKV") == .video)
        #expect(Category(fileName: "setup.dmg") == .programs)
        #expect(Category(fileName: "archive.tar.gz") == .archives)
        #expect(Category(fileName: "README") == .other)
    }

    @Test func parsesPastedAddresses() {
        let urls = NewDownloadPanel.parse("https://a.com/x.zip\n  http://b.org/y.iso junk ftp://c/z file:///etc/hosts")
        #expect(urls.map(\.absoluteString) == ["https://a.com/x.zip", "http://b.org/y.iso"])
    }
}
