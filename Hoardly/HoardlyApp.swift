import SwiftUI

@main
struct HoardlyApp: App {
    @State private var bridge = LocalBridge()

    var body: some Scene {
        WindowGroup {
            ContentView(bridge: bridge)
                .task { bridge.start() }
        }
    }
}

struct ContentView: View {
    let bridge: LocalBridge

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(bridge.status).font(.headline)
            HStack {
                Text("Pairing token:")
                Text(bridge.token).monospaced().textSelection(.enabled)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(bridge.token, forType: .string)
                }
            }
            List(bridge.log.reversed()) { entry in
                Text(entry.date, style: .time) + Text("  " + entry.text)
            }
        }
        .padding()
        .frame(minWidth: 560, minHeight: 360)
    }
}
