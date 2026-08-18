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
            StatusLabel(headline: refresher.headline, style: refresher.menuBarStyle)
                .task { refresher.start() }
        }
        .menuBarExtraStyle(.window)
    }
}
