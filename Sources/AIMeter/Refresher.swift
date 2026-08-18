import AppKit
import Foundation
import Observation
import SwiftUI

/// 聚合三個資料源。每一個都有自己的節奏、自己的錯誤——
/// Higgsfield 憑證過期不該讓 Claude 那一格也跟著消失。
@MainActor
@Observable
final class Refresher {
    // 顏色取各家自己的識別色，符號盡量貼近各家的標誌，
    // 同時保持四個輪廓差異夠大——選單列會把顏色吃掉，那裡只剩形狀可以分辨。
    let claude = SourceBox(
        title: "Claude Code", symbol: "sparkle",                    // 星芒
        brand: Brand(0.85, 0.47, 0.34),         // Claude 橙
        headlineMetricID: "sd"                  // 選單列顯示 7 天，不是 5 小時窗
    )
    let codex = SourceBox(
        title: "Codex", symbol: "terminal.fill",                    // >_ 終端機
        brand: Brand(0.31, 0.36, 0.91)          // Codex 藍紫
    )
    let openRouter = SourceBox(
        title: "OpenRouter", symbol: "arrow.left.arrow.right",      // 對向箭頭＝轉送
        brand: Brand(0.11, 0.12, 0.14)          // OpenRouter 近黑
    )
    let higgsfield = SourceBox(
        title: "Higgsfield", symbol: "scribble",                    // 曲線緞帶
        brand: Brand(0.80, 0.95, 0.18)          // Higgsfield 螢光黃綠
    )

    /// 只有啟用的來源才會出現。停用的是**不存在**，不是灰掉——
    /// 沒裝 Higgsfield 就不該在畫面上看到 Higgsfield。
    var boxes: [SourceBox] {
        SourceKind.allCases.filter { config.enabled($0) }.map(box)
    }

    func box(_ kind: SourceKind) -> SourceBox {
        switch kind {
        case .claudeCode: return claude
        case .codex: return codex
        case .openRouter: return openRouter
        case .higgsfield: return higgsfield
        }
    }

    private func refresh(_ kind: SourceKind) async {
        switch kind {
        case .claudeCode: await refreshClaude()
        case .codex: await refreshCodex()
        case .openRouter: await refreshOpenRouter()
        case .higgsfield: await refreshHiggsfield()
        }
    }

    // MARK: 啟用／停用

    func isEnabled(_ kind: SourceKind) -> Bool { config.enabled(kind) }

    /// 停用不只是不顯示——連輪詢迴圈都會被拆掉，所以真的不會再發請求。
    func setEnabled(_ enabled: Bool, for kind: SourceKind) {
        guard config.enabled(kind) != enabled else { return }
        config.setEnabled(enabled, for: kind)
        do { try config.save() } catch {
            NSLog("[AIMeter] 寫入設定失敗: \(error)")
        }
        pause()
        resume()
    }

    private var config: AppConfig

    private var tasks: [Task<Void, Never>] = []
    private var observers: [NSObjectProtocol] = []

    init() {
        config = AppConfig.bootstrap()
    }

    /// 桌面面板（貼在桌布上的視窗）。開關會記住，重開 app 自動回來。
    var desktopPanelVisible: Bool = UserDefaults.standard.bool(forKey: "desktopPanelVisible") {
        didSet {
            UserDefaults.standard.set(desktopPanelVisible, forKey: "desktopPanelVisible")
            desktopPanelVisible ? desktopPanel.show(refresher: self) : desktopPanel.hide()
        }
    }

    private let desktopPanel = DesktopPanelWindow()

    /// 選單列項目的寬度樣式。選單列塞不下時，排在後面的項目會直接不被畫出來，
    /// 所以要讓使用者能自己把它縮窄。
    var menuBarStyle: MenuBarStyle = MenuBarStyle.stored {
        didSet { MenuBarStyle.stored = menuBarStyle }
    }

    /// 選單列要顯示誰。改了就記住，重開 app 還在。
    var selection: MenuBarSelection = MenuBarSelection.stored {
        didSet { MenuBarSelection.stored = selection }
    }

    /// 背景更新頻率。改了要立刻重排迴圈，否則要等到下一輪才生效——
    /// 使用者切到「省電」卻看著它照舊每分鐘更新，會以為設定沒作用。
    var cadence: RefreshCadence = RefreshCadence.stored {
        didSet {
            guard cadence != oldValue else { return }
            RefreshCadence.stored = cadence
            pause()
            resume()
        }
    }

    // MARK: 生命週期

    func start() {
        observeSleepWake()
        resume()
        // 上次關 app 時開著的話，這次也要自己回來。
        if desktopPanelVisible { desktopPanel.show(refresher: self) }
    }

    /// 背景節奏刻意放得很鬆。選單列上的數字只要「大致是對的」就夠用，
    /// 真的要看細節的時候會點開面板，而那時候 panelDidOpen() 會立刻抓一次。
    /// 與其每 5 分鐘吵醒一次 Wi-Fi，不如在你真的在看的時候才拿最新的。
    /// 停用的來源連迴圈都不建——不只是不顯示，是完全不花成本。
    private func resume() {
        guard tasks.isEmpty else { return }
        tasks = SourceKind.allCases
            .filter { config.enabled($0) }
            .map { kind in
                loop(seconds: cadence.interval(for: kind)) { await self.refresh(kind) }
            }
    }

    private func pause() {
        tasks.forEach { $0.cancel() }
        tasks = []
    }

    /// 螢幕睡著或系統睡著時完全停止輪詢。
    /// 沒有這個的話，闔上蓋子整晚它還是每 15 分鐘吵醒一次無線電——
    /// 而那段時間根本沒有人在看選單列。
    private func observeSleepWake() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter

        func on(_ name: Notification.Name, _ action: @escaping () -> Void) {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated { action() }
                }
            )
        }

        on(NSWorkspace.screensDidSleepNotification) { [weak self] in self?.pause() }
        on(NSWorkspace.willSleepNotification) { [weak self] in self?.pause() }
        // 醒來時 resume() 會讓每個迴圈先跑一次 body，所以數字馬上就是新的。
        on(NSWorkspace.screensDidWakeNotification) { [weak self] in self?.resume() }
        on(NSWorkspace.didWakeNotification) { [weak self] in self?.resume() }
    }

    // MARK: 取數時機

    func refreshNow() {
        for kind in SourceKind.allCases where config.enabled(kind) {
            Task { await refresh(kind) }
        }
    }

    /// 面板打開的那一刻——這才是使用者真正在看的時候，值得花成本。
    /// 有節流，連續開關面板不會每次都重抓。
    func panelDidOpen() {
        for kind in SourceKind.allCases where config.enabled(kind) {
            let threshold = cadence.openThreshold(for: kind)
            if let last = box(kind).lastFetch, Date().timeIntervalSince(last) < threshold { continue }
            Task { await refresh(kind) }
        }
    }

    private func loop(seconds: UInt64, _ body: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        Task { @MainActor in
            while !Task.isCancelled {
                await body()
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }

    // MARK: 各源更新

    private func refreshClaude() async {
        claude.beginRefresh()
        do {
            let usage = try ClaudeCodeSource.read()
            // 重置時間只有 statusline 鏡射檔有；沒有的話就只是少了倒數，不影響百分比。
            let mirror = ClaudeRateLimitMirror.read()

            var metrics = [
                Self.remainingMetric(
                    id: "fh", label: "5 小時窗",
                    usedPercent: Double(usage.fiveHour),
                    detail: Self.resetDetail(mirror?.fiveHour.timeUntilReset),
                    warning: 40, critical: 20
                ),
                Self.remainingMetric(
                    id: "sd", label: "7 天",
                    usedPercent: Double(usage.sevenDay),
                    detail: Self.resetDetail(mirror?.sevenDay.timeUntilReset),
                    warning: 30, critical: 10
                ),
            ]
            if let extra = usage.extraUsage, extra > 0 {
                metrics.append(
                    Metric(
                        id: "xu",
                        label: "超額",
                        value: "已用 \(extra)%",     // 超額沒有「剩餘」可言
                        fraction: Double(extra) / 100,
                        alert: .warning
                    )
                )
            }
            // 這個檔只在 Claude 桌面 App 跑著的時候才更新，舊數字不能當現況用。
            let note = usage.isStale ? "資料已 \(Self.relative(usage.age)) 未更新（Claude.app 沒在跑？）" : nil
            claude.succeeded(metrics: metrics, note: note)
        } catch {
            claude.failed(error)
        }
    }

    private func refreshCodex() async {
        codex.beginRefresh()
        do {
            let status = try await CodexSource.fetch()
            let metrics = status.windows.map { window in
                Self.remainingMetric(
                    id: window.id, label: window.label,
                    usedPercent: window.usedPercent,
                    detail: Self.resetDetail(window.timeUntilReset),
                    warning: 30, critical: 10
                )
            }
            // 方案名稱（prolite 之類）不顯示：它從來不會變，佔一行卻不帶任何決策資訊。
            // 只有真的有 credit 餘額時才值得補一行——而且 hasCredits 為假時不能印 "0"，
            // 那會被誤讀成「額度用光了」。
            let note = (status.hasCredits ? status.creditBalance.map { "credits \($0)" } : nil)
            codex.succeeded(metrics: metrics, note: note)
        } catch {
            codex.failed(error)
        }
    }

    private func refreshOpenRouter() async {
        openRouter.beginRefresh()
        let results = await OpenRouterSource.fetchAll()

        // 兩個帳號都掛才算整格失敗；一個掛就只讓那一列顯示錯誤。
        let successes = results.compactMap { try? $0.result.get() }
        if successes.isEmpty, let firstError = results.compactMap({ $0.result.failureError }).first {
            openRouter.failed(firstError)
            return
        }

        let metrics = results.map { entry -> Metric in
            switch entry.result {
            case .success(let balance):
                return Metric(
                    id: entry.label,
                    style: .group,
                    label: entry.label,
                    detail: "額度 \(Self.money(balance.totalCredits))，已用 \(Self.money(balance.totalUsage))",
                    value: Self.money(balance.remaining),
                    fraction: nil,
                    alert: level(remaining: balance.remaining, warning: 15, critical: 5),
                    children: keyBreakdown(for: balance)
                )
            case .failure(let error):
                return Metric(
                    id: entry.label,
                    style: .group,
                    label: entry.label,
                    value: "讀取失敗",
                    fraction: nil,
                    alert: .warning
                )
                .describing(error)
            }
        }

        // 不再顯示跨帳號的累計已用：每個帳號那一列的說明本來就寫著各自的
        // 「額度 $X，已用 $Y」，再加一行總和是重複資訊。
        openRouter.succeeded(metrics: metrics, note: nil)
    }

    private func refreshHiggsfield() async {
        higgsfield.beginRefresh()
        do {
            let status = try await HiggsfieldSource.fetch()
            let metric = Metric(
                id: "credits",
                label: "Credits",
                value: Self.integer(status.credits),
                fraction: nil,
                alert: level(remaining: Double(status.credits), warning: 1500, critical: 500)
            )
            higgsfield.succeeded(metrics: [metric], note: "\(status.plan) 方案 · \(status.email)")
        } catch {
            higgsfield.failed(error)
        }
    }

    /// 每把 key 的用量對照它自己設的上限。
    ///
    /// 最後那列「其他」是刻意的：已刪除的金鑰、以及 /keys 看不到的後台金鑰，
    /// 它們的花費都落在這裡。少了那一列，帳號明細會加總不到實際花掉的錢，
    /// 而且不會有任何提示。
    private func keyBreakdown(for balance: OpenRouterBalance) -> [Metric] {
        var rows = balance.keys.map { key -> Metric in
            if let limit = key.limit, limit > 0 {
                let remaining = key.limitRemaining ?? (limit - key.usage)
                let remainingFraction = max(0, remaining / limit)
                return Metric(
                    id: "\(balance.label)/\(key.name)",
                    label: key.name,
                    detail: "已用 \(Self.money(key.usage))",
                    value: "\(Self.money(remaining)) / \(Self.money(limit))",
                    fraction: min(1, max(0, key.usage / limit)),   // 條畫已用，數字講剩餘
                    alert: level(remaining: remainingFraction, warning: 0.25, critical: 0.10)
                )
            }
            return Metric(
                id: "\(balance.label)/\(key.name)",
                label: key.name,
                detail: "未設上限",
                value: "已用 \(Self.money(key.usage))",
                fraction: nil
            )
        }

        let unattributed = balance.unattributedUsage
        // 幾分錢的浮點誤差不值得佔一行。
        if unattributed > 0.01 {
            rows.append(
                Metric(
                    id: "\(balance.label)/unattributed",
                    label: "其他",
                    detail: "已刪除或後台建立的金鑰",
                    value: "已用 \(Self.money(unattributed))",
                    fraction: nil
                )
            )
        }
        return rows
    }

    // MARK: 選單列標題

    struct Headline {
        var symbol: String
        /// 選單列的徽章要自己畫，所以顏色得跟著 headline 一起傳出去。
        var brand: Brand
        var text: String
        var alert: AlertLevel
        /// 釘住某一源時，別的源出事了還是得讓人知道，否則就變成
        /// 「畫面上看起來沒事」——那正是最危險的狀態。
        var otherCritical = false
    }

    /// 釘住的來源如果被停用，退回自動——否則選單列會空著，
    /// 而使用者不會知道原因。
    private func box(for selection: MenuBarSelection) -> SourceBox? {
        let pinned: SourceBox?
        switch selection {
        case .auto: return nil
        case .claude: pinned = claude
        case .codex: pinned = codex
        case .openRouter: pinned = openRouter
        case .higgsfield: pinned = higgsfield
        }
        return boxes.contains { $0 === pinned } ? pinned : nil
    }

    /// 一個來源在選單列上的代表數字：優先取警戒最高的那一列，否則取第一列。
    /// 選單列上代表這個來源的那一個指標。
    ///
    /// 指定了 headlineMetricID 就照它——即使同一張卡裡有別的指標更嚴重。
    /// 那個「更嚴重的別人」不會被吞掉：它會讓 otherCritical 亮起記號，
    /// 但不會把使用者指定要看的數字換掉。
    private func headline(for box: SourceBox) -> Headline? {
        let preferred = box.headlineMetricID.flatMap { id in
            box.metrics.first { $0.id == id }
        }
        guard let metric = preferred
                ?? box.metrics.first(where: { $0.effectiveAlert == box.alert })
                ?? box.metrics.first
        else { return nil }

        return Headline(
            symbol: box.symbol, brand: box.brand,
            text: metric.value, alert: metric.effectiveAlert,
            // 同一張卡裡有沒被顯示出來、而且已經 critical 的指標？
            otherCritical: box.metrics.contains { $0.id != metric.id && $0.effectiveAlert == .critical }
        )
    }

    /// 釘住了就照釘住的顯示；`.auto` 才回到「平常 Claude、有警戒就換人」的邏輯。
    var headline: Headline {
        if let pinned = box(for: selection) {
            var result = headline(for: pinned)
                ?? Headline(symbol: pinned.symbol, brand: pinned.brand, text: "—", alert: .normal)
            result.otherCritical = result.otherCritical
                || boxes.contains { $0 !== pinned && $0.alert == .critical }
            return result
        }

        let candidates = boxes.compactMap(headline(for:))
        if let worst = candidates.filter({ $0.alert > .normal }).max(by: { $0.alert < $1.alert }) {
            return worst
        }
        return candidates.first
            ?? Headline(symbol: "gauge.with.needle", brand: Brand(0.5, 0.5, 0.52), text: "—", alert: .normal)
    }

    /// 數字講**剩餘**，進度條講**已用**——兩者刻意不同步。
    ///
    /// 數字用剩餘：使用者的 Claude Code statusline 顯示的就是剩餘（那支腳本算 100 - used），
    /// 兩邊講同一件事卻反過來的話，每次對照都要心算。
    ///
    /// 條用已用：「條很短」直覺上像「還沒用多少」，要多想一秒才會意識到是快用完了。
    /// 填滿才是逼近極限，那是通用的閱讀方式。macOS 自己的儲存空間指示器正是這個組合——
    /// 條隨已使用量填滿，旁邊的文字寫「可用 86 GB」。
    ///
    /// 文字上：無標示 = 剩餘；只有「沒有剩餘可言」的東西（超額、沒設上限的 key）才標「已用」。
    nonisolated static func remainingMetric(
        id: String,
        label: String,
        usedPercent: Double,
        detail: String?,
        warning: Double,
        critical: Double
    ) -> Metric {
        let remaining = max(0, 100 - usedPercent)
        return Metric(
            id: id,
            label: label,
            detail: detail,
            value: "\(Int(remaining.rounded()))%",
            fraction: min(1, max(0, usedPercent / 100)),   // 條畫已用
            alert: remaining <= critical ? .critical : (remaining <= warning ? .warning : .normal)
        )
    }

    // MARK: 小工具

    private func level(remaining: Double, warning: Double, critical: Double) -> AlertLevel {
        remaining < critical ? .critical : (remaining < warning ? .warning : .normal)
    }

    /// 「2h14m 後重置」。拿不到重置時間就沒有這一行。
    nonisolated static func resetDetail(_ resetsIn: TimeInterval?) -> String? {
        resetsIn.map { "\(countdown($0)) 後重置" }
    }

    nonisolated static func countdown(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d\(hours)h" }
        if hours > 0 { return "\(hours)h\(minutes)m" }
        return "\(minutes)m"
    }

    nonisolated static func money(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    nonisolated static func integer(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    nonisolated static func relative(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        if minutes < 60 { return "\(minutes) 分鐘" }
        let hours = minutes / 60
        return hours < 24 ? "\(hours) 小時" : "\(hours / 24) 天"
    }
}

private extension Result {
    var failureError: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

private extension Metric {
    /// 把錯誤訊息塞進 label 底下顯示用的欄位。
    func describing(_ error: Error) -> Metric {
        var copy = self
        copy.label = "\(label) — \(error.localizedDescription)"
        return copy
    }
}
