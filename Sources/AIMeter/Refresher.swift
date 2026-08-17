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
                Metric(
                    id: "fh",
                    label: "5 小時窗",
                    detail: Self.resetDetail(mirror?.fiveHour.timeUntilReset),
                    value: "\(usage.fiveHour)%",
                    fraction: Double(usage.fiveHour) / 100,
                    alert: level(percent: usage.fiveHour, warning: 60, critical: 80)
                ),
                Metric(
                    id: "sd",
                    label: "7 天",
                    detail: Self.resetDetail(mirror?.sevenDay.timeUntilReset),
                    value: "\(usage.sevenDay)%",
                    fraction: Double(usage.sevenDay) / 100,
                    alert: level(percent: usage.sevenDay, warning: 70, critical: 90)
                ),
            ]
            if let extra = usage.extraUsage, extra > 0 {
                metrics.append(
                    Metric(
                        id: "xu",
                        label: "超額",
                        value: "\(extra)%",
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
                Metric(
                    id: window.id,
                    label: window.label,
                    detail: Self.resetDetail(window.timeUntilReset),
                    value: "\(Int(window.usedPercent.rounded()))%",
                    fraction: window.usedPercent / 100,
                    alert: level(percent: Int(window.usedPercent.rounded()), warning: 70, critical: 90)
                )
            }
            var note = status.planType.map { "\($0) 方案" }
            // 只在真的有 credit 餘額時才提，不然 "0" 會被誤讀成「額度用光了」。
            if status.hasCredits, let balance = status.creditBalance {
                note = [note, "credits \(balance)"].compactMap { $0 }.joined(separator: " · ")
            }
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

        let spent = successes.reduce(0) { $0 + $1.totalUsage }
        openRouter.succeeded(metrics: metrics, note: "累計已用 \(Self.money(spent))")
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
    /// 最後那列「未歸戶」是刻意的：/keys 看不到從網頁後台建的金鑰，
    /// 少了那一列的話，帳號明細會加總不到帳號實際花掉的錢，而且不會有任何提示。
    private func keyBreakdown(for balance: OpenRouterBalance) -> [Metric] {
        var rows = balance.keys.map { key -> Metric in
            if let limit = key.limit, limit > 0 {
                let remaining = key.limitRemaining ?? (limit - key.usage)
                return Metric(
                    id: "\(balance.label)/\(key.name)",
                    label: key.name,
                    detail: "上限 \(Self.money(limit))，已用 \(Self.money(key.usage))",
                    value: "剩 \(Self.money(remaining))",
                    fraction: key.usage / limit,
                    alert: level(fraction: key.usage / limit, warning: 0.75, critical: 0.9)
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
                    label: "未歸戶（後台建的 key）",
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

    // MARK: 小工具

    private func level(percent: Int, warning: Int, critical: Int) -> AlertLevel {
        percent >= critical ? .critical : (percent >= warning ? .warning : .normal)
    }

    private func level(remaining: Double, warning: Double, critical: Double) -> AlertLevel {
        remaining < critical ? .critical : (remaining < warning ? .warning : .normal)
    }

    private func level(fraction: Double, warning: Double, critical: Double) -> AlertLevel {
        fraction >= critical ? .critical : (fraction >= warning ? .warning : .normal)
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
