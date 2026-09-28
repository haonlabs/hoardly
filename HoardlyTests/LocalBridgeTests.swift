import Foundation
import Testing
@testable import Hoardly

struct LocalBridgeTests {
    private func raw(_ headers: String, _ body: String) -> Data {
        Data("POST /add HTTP/1.1\r\n\(headers)Content-Length: \(body.utf8.count)\r\n\r\n\(body)".utf8)
    }

    @Test func parsesCompleteRequestOnly() throws {
        let full = raw("X-Hoardly-Token: t\r\n", #"{"url":"https://a.b/c.zip"}"#)
        #expect(HTTPRequest(full.dropLast(3)) == nil)
        let request = try #require(HTTPRequest(full))
        #expect(request.method == "POST" && request.path == "/add")
        #expect(request.headers["x-hoardly-token"] == "t")
        #expect(String(decoding: request.body, as: UTF8.self) == #"{"url":"https://a.b/c.zip"}"#)
    }

    @Test func enforcesOriginTokenAndScheme() throws {
        let bridge = LocalBridge()
        let token = "X-Hoardly-Token: \(bridge.token)\r\n"
        let ok = #"{"url":"https://a.b/c.zip"}"#
        func status(_ headers: String, _ body: String) throws -> Int {
            try bridge.handle(#require(HTTPRequest(raw(headers, body)))).0
        }
        #expect(try status(token, ok) == 200)
        #expect(try status("Origin: chrome-extension://abc\r\n" + token, ok) == 200)
        #expect(try status("Origin: https://evil.example\r\n" + token, ok) == 403)
        #expect(try status("X-Hoardly-Token: wrong\r\n", ok) == 401)
        #expect(try status(token, #"{"url":"file:///etc/passwd"}"#) == 400)
    }
}
