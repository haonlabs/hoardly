import SafariServices
import SwiftUI

enum Links {
    static let repo = URL(string: "https://github.com/haonlabs/hoardly")!
    // ponytail: until the store listings are live, every browser points at the README's install section.
    static let installExtension = URL(string: "https://github.com/haonlabs/hoardly#browser-extension")!
    static let safariExtensionID = "id.haonlabs.hoardly.SafariExtension"
}

/// First-run setup (M6): add the extension to each installed browser, connect, open at login.
struct WelcomeView: View {
    let bridge: LocalBridge
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage("onboarded") private var onboarded = false
    @State private var safariEnabled = false

    private struct Browser: Identifiable {
        let name: String
        let id: String // bundle identifier
    }

    private static let browsers = [
        Browser(name: "Safari", id: "com.apple.Safari"),
        Browser(name: "Google Chrome", id: "com.google.Chrome"),
        Browser(name: "Helium", id: "net.imput.helium"),
        Browser(name: "Arc", id: "company.thebrowser.Browser"),
        Browser(name: "Brave", id: "com.brave.Browser"),
        Browser(name: "Microsoft Edge", id: "com.microsoft.edgemac"),
        Browser(name: "Vivaldi", id: "com.vivaldi.Vivaldi"),
        Browser(name: "Opera", id: "com.operasoftware.Opera"),
        Browser(name: "Firefox", id: "org.mozilla.firefox"),
    ]

    private var installed: [(Browser, URL)] {
        Self.browsers.compactMap { b in NSWorkspace.shared.urlForApplication(withBundleIdentifier: b.id).map { (b, $0) } }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 84, height: 84)
                Text("Welcome to Hoardly").font(.largeTitle.bold())
                Text("Faster, resumable downloads from every browser.").foregroundStyle(.secondary)
            }
            .padding(.top, 24)

            Form {
                Section("1. Add Hoardly to your browsers") {
                    ForEach(installed, id: \.0.id) { browser, url in
                        LabeledContent {
                            if browser.id == "com.apple.Safari" {
                                if safariEnabled {
                                    Label("Turned on", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                                } else {
                                    Button("Turn On in Safari…") { SFSafariApplication.showPreferencesForExtension(withIdentifier: Links.safariExtensionID) }
                                }
                            } else {
                                Button("Get Extension") {
                                    NSWorkspace.shared.open([Links.installExtension], withApplicationAt: url, configuration: .init())
                                }
                            }
                        } label: {
                            Label {
                                Text(browser.name)
                            } icon: {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 20, height: 20)
                            }
                        }
                    }
                }
                Section("2. Connect") {
                    Text("The first time a browser's extension reaches Hoardly, a dialog asks you to connect it. Click Connect.")
                        .foregroundStyle(.secondary)
                    LabeledContent("Hoardly", value: bridge.status)
                }
                Section("3. Stay ready") {
                    OpenAtLoginToggle()
                    Text("Browsers can only hand downloads to Hoardly while it's running; otherwise they download as usual.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Done") {
                    onboarded = true
                    dismissWindow()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom])
        }
        .frame(width: 520, height: 700)
        .task { await refreshSafari() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshSafari() } // back from Safari's settings
        }
    }

    private func refreshSafari() async {
        safariEnabled = (try? await SFSafariExtensionManager.stateOfSafariExtension(withIdentifier: Links.safariExtensionID))?.isEnabled ?? false
    }
}
