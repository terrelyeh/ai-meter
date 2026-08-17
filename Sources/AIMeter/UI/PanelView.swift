import AppKit
import SwiftUI

struct PanelView: View {
    @Bindable var refresher: Refresher
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(refresher.boxes, id: \.title) { box in
                SourceCard(box: box)
            }

            Divider().padding(.top, 4)
            footer
        }
        .padding(12)
        .frame(width: 328)
        // 面板打開才是使用者真的在看的時候，這時候值得花成本抓最新的。
        .onAppear { refresher.panelDidOpen() }
    }

    /// 面板只留「現在要做的事」：重抓、開設定、關掉。
    /// 其餘設定都搬到設定視窗——四個控制項塞在這裡已經開始擠了。
    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                refresher.refreshNow()
            } label: {
                Label("重新整理", systemImage: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)

            Spacer()

            Button {
                // LSUIElement 的 app 預設不會被帶到前景，不 activate 的話
                // 視窗會開在別的 app 後面，看起來像沒反應。
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: SettingsWindow.id)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("設定")

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("結束")
        }
    }
}

/// 一個來源一張卡。用底色分組比用分隔線的區隔感強得多——
/// 分隔線只是一條細線，底色是一整塊面積。
private struct SourceCard: View {
    @Bindable var box: SourceBox
    /// 展開狀態留在 UI 這層，重新整理資料不會把使用者展開的東西收回去。
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            content
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay(
            // 平時用中性邊框：拿識別色當邊框的話，OpenRouter 那張近黑色的卡
            // 邊框會直接消失，四張卡看起來不成套。警戒時才換成識別色。
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(
                    box.alert > .normal ? box.accent.opacity(0.5) : Color.primary.opacity(0.1),
                    lineWidth: 1
                )
        )
    }

    // MARK: 標題列

    private var header: some View {
        HStack(spacing: 7) {
            badge
            Text(box.title)
                .font(.system(size: 12.5, weight: .semibold))
            Spacer(minLength: 6)
            trailingStatus
        }
    }

    /// 彩色徽章。四個灰色 SF Symbol 掃起來全長一樣，加了顏色才分得出誰是誰。
    private var badge: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(box.accent)
            .frame(width: 19, height: 19)
            .overlay(
                Image(systemName: box.symbol)
                    .font(.system(size: 10, weight: .semibold))
                    // 亮底配深圖示、暗底配白圖示，不然螢光黃綠上的白圖示會消失
                    .foregroundStyle(box.brand.onColor)
            )
            .overlay(
                // 近黑色的徽章在深色模式下會融進卡片背景，靠這條細邊維持輪廓
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
            )
    }

    @ViewBuilder
    private var trailingStatus: some View {
        if box.isRefreshing {
            // 數字常常前後一樣，沒有這個轉圈使用者會以為「重新整理」沒作用。
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.65)
                .frame(width: 12, height: 12)
        } else if let lastFetch = box.lastFetch {
            // 帶到秒——只到分鐘的話，同一分鐘內重新整理畫面完全不會動。
            Text(Self.clock.string(from: lastFetch))
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    // MARK: 內容

    @ViewBuilder
    private var content: some View {
        switch box.status {
        case .loading:
            Text("讀取中…")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

        case .ok:
            metricList
            if let note = box.note { caption(note) }

        // 舊數字照顯示，但要明講它是舊的——不然使用者會拿一個過期的數字做決定。
        case .degraded(let message, let hint):
            metricList
            problem(message: message, hint: hint, icon: "clock.badge.exclamationmark", tint: .secondary)
            if let lastSuccess = box.lastSuccess {
                caption("顯示的是 \(Self.clock.string(from: lastSuccess)) 的資料")
            }

        // 失敗的區塊要留在原地講清楚發生什麼事。整格消失的話，
        // 你會以為自己看到的是「沒問題」。
        case .failed(let message, let hint):
            problem(message: message, hint: hint, icon: "exclamationmark.triangle.fill", tint: .orange)
        }
    }

    private var metricList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(box.metrics) { metric in
                MetricRow(
                    metric: metric,
                    isExpanded: expanded.contains(metric.id),
                    accent: box.accent,
                    onToggle: {
                        if expanded.contains(metric.id) {
                            expanded.remove(metric.id)
                        } else {
                            expanded.insert(metric.id)
                        }
                    }
                )
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func problem(message: String, hint: String?, icon: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let hint {
                    Text(hint)
                        .font(.system(size: 10.5).monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
