import AppKit
import SwiftUI

/// 桌面面板：一個貼在桌布上的無邊框視窗。
///
/// 這不是 WidgetKit 的 widget，是刻意的。真正的 widget 必須是 app extension，
/// 而 macOS 的 extension 強制沙盒——沙盒一開，四個資料源死三個（讀不到 Claude 的
/// 資料檔、不能執行 codex 與 higgsfield 的 binary）。要把資料從主程式餵進去就得靠
/// App Group，而 App Group 的識別碼在 macOS 上必須以 Team ID 開頭，那需要開發者帳號。
///
/// 換成自己的視窗之後，這些限制一個都不存在，而且四個來源的程式碼一行都不用改。
/// 代價是它不會出現在系統的 widget 資源庫裡。
@MainActor
final class DesktopPanelWindow {
    private var window: NSWindow?
    private var moveObserver: NSObjectProtocol?

    private static let originKey = "desktopPanelOrigin"

    var isVisible: Bool { window != nil }

    func show(refresher: Refresher) {
        if let window {
            window.orderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: DesktopPanelView(refresher: refresher))
        let window = DraggableDesktopWindow(contentViewController: hosting)

        window.styleMask = [.borderless, .fullSizeContentView]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true      // 整塊都能拖，不用做把手
        window.isReleasedWhenClosed = false

        // 一般視窗之下（會被任何 app 視窗蓋住，像桌面 widget），但在桌面圖示之上。
        //
        // 不能用 .desktopIconWindow：那正是 Finder 桌面圖示視窗所在的層，
        // 排在它後面就等於被一片全螢幕的視窗蓋住，所有點擊都會被它吃掉——
        // 看得到卻點不到。normal - 1 在所有 app 視窗之下、桌面之上，才點得到。
        window.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
        // 切換 Space 時跟著在，而且不要出現在 ⌘Tab 與 Mission Control 的視窗循環裡。
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        restoreOrigin(of: window)
        window.orderFront(nil)

        // 拖到哪就記在哪，不然每次開啟都跳回預設位置。
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: window, queue: .main
        ) { note in
            guard let moved = note.object as? NSWindow else { return }
            MainActor.assumeIsolated { Self.saveOrigin(of: moved) }
        }

        self.window = window
    }

    func hide() {
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
            self.moveObserver = nil
        }
        window?.close()
        window = nil
    }

    // MARK: 位置

    private static func saveOrigin(of window: NSWindow) {
        let origin = window.frame.origin
        UserDefaults.standard.set([origin.x, origin.y], forKey: originKey)
    }

    private func restoreOrigin(of window: NSWindow) {
        if let saved = UserDefaults.standard.array(forKey: Self.originKey) as? [Double],
           saved.count == 2 {
            let origin = NSPoint(x: saved[0], y: saved[1])
            // 螢幕換了、解析度變了都可能讓舊座標落在畫面外，那會變成一個看不見的視窗。
            if NSScreen.screens.contains(where: { $0.visibleFrame.contains(origin) }) {
                window.setFrameOrigin(origin)
                return
            }
        }
        guard let screen = NSScreen.main else { return }
        let area = screen.visibleFrame
        window.setFrameTopLeftPoint(
            NSPoint(x: area.maxX - window.frame.width - 24, y: area.maxY - 24)
        )
    }
}

/// 無邊框視窗的 `canBecomeKey` 預設是 false，於是 App 一失去焦點就完全收不到滑鼠事件——
/// 症狀是「剛開時拖得動，過一下就點不到了」。覆寫掉才會一直可以拖。
private final class DraggableDesktopWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }   // 不搶主視窗，避免影響選單列面板
}

private struct DesktopPanelView: View {
    @Bindable var refresher: Refresher

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if refresher.boxes.isEmpty {
                Text("沒有啟用任何來源")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(refresher.boxes, id: \.title) { box in
                    SourceCard(box: box, emphasis: .desktop)
                }
            }
        }
        .padding(14)
        .frame(width: 300)
        .background(
            // 桌布什麼顏色都可能，太透明的話卡片跟底就分不開了。
            // 厚一點的材質先給一個穩定的底，卡片才有東西可以浮在上面。
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thickMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }
}
