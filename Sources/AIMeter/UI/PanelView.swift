import AppKit
import SwiftUI

struct PanelView: View {
    @Bindable var refresher: Refresher
    @State private var launchAtLogin = LoginItem.isInstalled

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if refresher.boxes.isEmpty {
                // 全關掉時面板會空無一物，得告訴使用者東西在哪、怎麼開回來。
                Text("目前沒有啟用任何來源。\n點下方的齒輪 → 顯示項目，把要看的打開。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
            } else {
                ForEach(refresher.boxes, id: \.title) { box in
                    SourceCard(box: box)
                }
            }

            Divider().padding(.top, 4)
            footer
        }
        .padding(12)
        .frame(width: 328)
        // 面板打開才是使用者真的在看的時候，這時候值得花成本抓最新的。
        .onAppear { refresher.panelDidOpen() }
    }

    /// 設定全部收進齒輪選單，面板底部只留一列。
    ///
    /// 五個控制項常駐時，設定區的份量幾乎跟上面四張資料卡一樣重——但這些設定
    /// 你幾乎不會動。真正值得一直看得到的只有「重新整理」。
    ///
    /// 用**選單**而不是獨立視窗：選單就地彈出，不用開視窗、不用 NSApp.activate，
    /// 也不會多一個要維護的 scene。之前那個設定視窗被拿掉正是因為那些代價。
    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                refresher.refreshNow()
            } label: {
                Label("重新整理", systemImage: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)

            Spacer()

            settingsMenu

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

    private var settingsMenu: some View {
        Menu {
            // 全部攤平在同一層，用 Section 分組。
            //
            // 原本三組是巢狀子選單，但那要「點開齒輪 → 再把滑鼠移到某一項 → 等它展開」，
            // 多一步而且要停住等 hover。inline 的 Picker 會直接展開成帶勾勾的選項，
            // 一眼看完、一次點到。選單變長，但長選單比多一層互動好。
            Section("顯示項目") {
                ForEach(SourceKind.allCases) { kind in
                    Toggle(kind.title, isOn: Binding(
                        get: { refresher.isEnabled(kind) },
                        set: { refresher.setEnabled($0, for: kind) }
                    ))
                }
            }

            Section("選單列顯示") {
                Picker("", selection: $refresher.selection) {
                    ForEach(MenuBarSelection.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.inline)
            }

            Section("選單列樣式") {
                Picker("", selection: $refresher.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.inline)
            }

            Section("更新頻率") {
                Picker("", selection: $refresher.cadence) {
                    ForEach(RefreshCadence.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.inline)
            }

            Divider()

            Toggle("桌面面板", isOn: $refresher.desktopPanelVisible)
            Toggle("開機啟動", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    LoginItem.set(enabled: enabled)
                }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 11))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)      // 齒輪本身就夠明顯，再加箭頭只是噪音
        .fixedSize()
        .help("設定 — 更新頻率：\(refresher.cadence.detail)。睡眠時一律停止輪詢，打開面板一定會抓最新的。")
    }
}

/// 卡片要多用力把自己跟背景分開。
enum CardEmphasis {
    /// 選單列面板：底下已經是系統的彈出視窗背景，淡淡一層就夠。
    case panel
    /// 桌面面板：底下是桌布，淡色調完全看不見，卡片得是一個真正的表面。
    case desktop

    var fill: Color {
        switch self {
        case .panel: return Color.primary.opacity(0.045)
        // 0.45 是「看得出是一塊表面」與「還透得出桌布」的折衷。
        // 再高會白得像貼紙，再低就跟毛玻璃底融在一起。
        case .desktop: return Color(nsColor: .controlBackgroundColor).opacity(0.45)
        }
    }

    var border: Double {
        switch self {
        case .panel: return 0.1
        // 底色透了之後，分隔就得靠邊框與陰影撐住。
        case .desktop: return 0.28
        }
    }

    var shadow: Double {
        switch self {
        case .panel: return 0          // 彈出視窗裡加陰影只會變髒
        case .desktop: return 0.18     // 讓卡片浮在毛玻璃之上
        }
    }
}

/// 一個來源一張卡。用底色分組比用分隔線的區隔感強得多——
/// 分隔線只是一條細線，底色是一整塊面積。
///
/// 選單列面板與桌面面板共用同一張卡，兩邊的樣子才不會漂移。
struct SourceCard: View {
    @Bindable var box: SourceBox
    var emphasis: CardEmphasis = .panel
    /// 展開狀態留在 UI 這層，重新整理資料不會把使用者展開的東西收回去。
    @State private var expanded: Set<String> = []
    @State private var isHovered = false

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
                .fill(emphasis.fill)
                // 滑過時底色再疊薄薄一層，讓「現在在看哪一張」有回應。
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(isHovered ? 0.05 : 0))
                )
                .shadow(
                    color: .black.opacity(emphasis.shadow),
                    radius: isHovered ? 7 : 4,
                    y: isHovered ? 2 : 1
                )
        )
        .overlay(
            // 平時用中性邊框：拿識別色當邊框的話，OpenRouter 那張近黑色的卡
            // 邊框會直接消失，四張卡看起來不成套。警戒時才換成識別色。
            // 滑過時改用識別色，順便強化「這張是誰」。
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        // 位移只有 1pt：常駐工具的動效要克制，做大了每次滑過都在跳。
        .offset(y: isHovered ? -1 : 0)
        .animation(.easeOut(duration: 0.14), value: isHovered)
        .onHover { isHovered = $0 }
    }

    private var borderColor: Color {
        if box.alert > .normal { return box.accent.opacity(0.6) }
        if isHovered { return box.accent.opacity(0.45) }
        return Color.primary.opacity(emphasis.border)
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

    // 列距要拉得比列內間距大，群組才分得開（見 MetricRow.plain 的說明）。
    private var metricList: some View {
        VStack(alignment: .leading, spacing: 12) {
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
