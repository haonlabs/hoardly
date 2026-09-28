import Sparkle
import SwiftUI

@main
struct HoardlyApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    private let manager = DownloadManager() // App is created once; @Observable does the view updates
    private let bridge = LocalBridge()
    private let updater = SPUStandardUpdaterController(startingUpdater: !DownloadManager.isTesting,
                                                       updaterDelegate: nil, userDriverDelegate: nil)

    init() {
        guard !DownloadManager.isTesting else { return }
        let manager = manager
        bridge.onAdd = { items in
            if UserDefaults.standard.bool(forKey: "confirmBrowserDownloads") {
                NewDownloadPanel.show(items, manager: manager)
            } else {
                for item in items { manager.add(item.url, headers: item.headers, fileName: item.fileName, stream: item.isStream) }
            }
        }
        bridge.start()
    }

    var body: some Scene {
        Window("Hoardly", id: "main") {
            MainView(manager: manager)
                .modifier(ShowWelcomeOnFirstLaunch())
        }
        .defaultSize(width: 1100, height: 560)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Download…") { NewDownloadPanel.show(manager: manager) }
                    .keyboardShortcut("n")
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updater.checkForUpdates(nil) }
            }
            CommandGroup(after: .appSettings) { SetUpBrowsersButton() }
        }

        Window("Welcome to Hoardly", id: "welcome") {
            WelcomeView(bridge: bridge)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(bridge: bridge)
        }

        MenuBarExtra {
            MenuBarView(manager: manager)
        } label: {
            // U4: total speed next to the icon while anything downloads.
            if manager.totalSpeed > 0 {
                Text("↓ " + manager.totalSpeed.formatted(.byteCount(style: .file)) + "/s")
            } else {
                Image(systemName: "arrow.down.circle")
            }
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarView: View {
    let manager: DownloadManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let active = manager.downloads.filter { $0.state == .running }
            if active.isEmpty {
                Text("No active downloads").foregroundStyle(.secondary)
            }
            ForEach(active) { d in
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.displayName).lineLimit(1).truncationMode(.middle)
                    if let fraction = d.fraction { ProgressView(value: fraction) }
                }
            }
            Divider()
            HStack {
                Button("New Download…") { NewDownloadPanel.show(manager: manager) }
                Spacer()
                Button("Open Hoardly") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding()
        .frame(width: 320)
    }
}

private struct ShowWelcomeOnFirstLaunch: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    @AppStorage("onboarded") private var onboarded = false

    func body(content: Content) -> some View {
        content.task { if !onboarded && !DownloadManager.isTesting { openWindow(id: "welcome") } }
    }
}

private struct SetUpBrowsersButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View { Button("Set Up Browsers…") { openWindow(id: "welcome") } }
}
