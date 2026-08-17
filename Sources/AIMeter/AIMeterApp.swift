import SwiftUI

@main
enum Entry {
    static func main() {
        if CommandLine.arguments.contains("--setup") {
            Setup.run()
        }
        if CommandLine.arguments.contains("--probe") {
            Probe.run()
        }
        AIMeterApp.main()
    }
}

struct AIMeterApp: App {
    @State private var refresher = Refresher()

    var body: some Scene {
        MenuBarExtra {
            PanelView(refresher: refresher)
        } label: {
            StatusLabel(headline: refresher.headline)
                .task { refresher.start() }
        }
        .menuBarExtraStyle(.window)

        // 用具名 Window 而不是 SwiftUI 的 Settings scene：這支是 LSUIElement，
        // 沒有主選單列，⌘, 沒有東西可以掛，所以得靠面板上的齒輪用 openWindow 叫出來。
        Window("AI Meter 設定", id: SettingsWindow.id) {
            SettingsView(refresher: refresher)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

enum SettingsWindow {
    static let id = "settings"
}
