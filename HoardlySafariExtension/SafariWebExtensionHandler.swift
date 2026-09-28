import SafariServices

/// Relays `browser.runtime.sendNativeMessage` from the Safari extension to the app's LocalBridge,
/// for when Safari won't let the extension fetch http://127.0.0.1 directly.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any] ?? [:]
        let path = message["path"] as? String ?? "/ping"

        guard path.hasPrefix("/"), let url = URL(string: "http://127.0.0.1:47801" + path) else {
            return Self.complete(context, ["status": 400, "error": "bad path"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(message["token"] as? String ?? "", forHTTPHeaderField: "X-Hoardly-Token")
        request.setValue("native", forHTTPHeaderField: "X-Hoardly-Via")
        request.httpBody = try? JSONSerialization.data(withJSONObject: message["body"] as? [String: Any] ?? [:])

        nonisolated(unsafe) let context = context
        URLSession.shared.dataTask(with: request) { data, response, error in
            var reply = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any] ?? [:]
            reply["status"] = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let error { reply["error"] = error.localizedDescription }
            Self.complete(context, reply)
        }.resume()
    }

    private static func complete(_ context: NSExtensionContext, _ reply: [String: Any]) {
        let item = NSExtensionItem()
        item.userInfo = [SFExtensionMessageKey: reply]
        context.completeRequest(returningItems: [item])
    }
}
