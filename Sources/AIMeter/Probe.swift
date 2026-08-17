import Foundation

/// `AIMeter --probe`：不開 UI，直接把三個資料源各跑一次印出來。
///
/// 存在的理由是「畫面上的數字對不對」很難用眼睛驗證。這條路走的是**跟 UI 完全同一份**
/// provider 程式碼，所以它印出來的東西對，選單列裡的就對；它壞了，就是真的壞了。
/// 錯誤路徑也能在這裡測（例如把 .env 改壞、把 CLI 藏起來）。
enum Probe {
    static func run() -> Never {
        let config = AppConfig.bootstrap()
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            // 只跑啟用中的來源。全部都跑的話，probe 會回報一個
            // 跟 app 實際在做的事不一樣的結果。
            for kind in SourceKind.allCases {
                guard config.enabled(kind) else {
                    print("\n\u{001B}[1m\(kind.title)\u{001B}[0m\n  · 已停用，略過")
                    continue
                }
                switch kind {
                case .claudeCode: await probeClaude()
                case .codex: await probeCodex()
                case .openRouter: await probeOpenRouter()
                case .higgsfield: await probeHiggsfield()
                }
            }
            semaphore.signal()
        }
        semaphore.wait()
        exit(0)
    }

    private static func heading(_ title: String) {
        print("\n\u{001B}[1m\(title)\u{001B}[0m")
    }

    private static func ok(_ line: String) { print("  ✓ \(line)") }
    private static func bad(_ line: String) { print("  ✗ \(line)") }

    private static func probeClaude() async {
        heading("Claude Code")
        print("  來源 \(ClaudeCodeSource.path.path(percentEncoded: false))")
        do {
            let usage = try ClaudeCodeSource.read()
            // 只在真的超額時才提。印 "超額 0%" 會讓人以為出事了。
            let extra = (usage.extraUsage ?? 0) > 0 ? "  ·  超額 \(usage.extraUsage!)%" : ""
            ok("5 小時窗 \(usage.fiveHour)%  ·  7 天 \(usage.sevenDay)%" + extra)
            let age = Int(usage.age / 60)
            let verdict = usage.isStale ? "⚠️ 已過期，Claude.app 可能沒在跑" : "新鮮"
            ok("樣本時間 \(usage.sampledAt.formatted(date: .omitted, time: .standard))（\(age) 分鐘前，\(verdict)）")

            print("  重置時間 \(ClaudeRateLimitMirror.path.path(percentEncoded: false))")
            if let mirror = ClaudeRateLimitMirror.read() {
                report("5 小時窗", mirror.fiveHour)
                report("7 天", mirror.sevenDay)
            } else {
                bad("讀不到鏡射檔——還沒有 Claude Code session 跑過 statusline")
                print("    → 開一個新的 Claude Code session；設定已指向 ~/.claude/statusline-mirror.sh")
            }
        } catch {
            bad(error.localizedDescription)
            if let hint = (error as? ClaudeCodeSource.Failure)?.hint { print("    → \(hint)") }
        }
    }

    private static func report(_ name: String, _ window: RateLimitWindow) {
        guard let resetsAt = window.resetsAt else {
            bad("\(name)：payload 裡沒有 resets_at")
            return
        }
        let countdown = window.timeUntilReset.map { Refresher.countdown($0) } ?? "已過"
        ok("\(name) 重置於 \(resetsAt.formatted(date: .abbreviated, time: .shortened))（\(countdown) 後）")
    }

    private static func probeCodex() async {
        heading("Codex")
        let found = CodexSource.candidatePaths
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) ?? "（找不到）"
        print("  CLI \(found) app-server")
        do {
            let status = try await CodexSource.fetch()
            for window in status.windows {
                let countdown = window.timeUntilReset.map { "\(Refresher.countdown($0)) 後重置" } ?? "重置時間未知"
                ok(String(format: "%@（%d 分鐘窗）用掉 %.0f%%  ·  %@",
                          window.label, window.windowMinutes, window.usedPercent, countdown))
            }
            ok("方案 \(status.planType ?? "未知")"
                + (status.hasCredits ? "  ·  credits \(status.creditBalance ?? "?")" : "  ·  無額外 credits"))
        } catch {
            bad(error.localizedDescription)
            if let hint = (error as? CodexSource.Failure)?.hint { print("    → \(hint)") }
        }
    }

    private static func probeOpenRouter() async {
        heading("OpenRouter")
        print("  金鑰 \(OpenRouterSource.envPath.path(percentEncoded: false))")
        for entry in await OpenRouterSource.fetchAll() {
            switch entry.result {
            case .success(let balance):
                ok(String(
                    format: "%@ 剩 $%.2f（額度 $%.2f，已用 $%.2f）",
                    balance.label, balance.remaining, balance.totalCredits, balance.totalUsage
                ))
                for key in balance.keys {
                    if let limit = key.limit, limit > 0 {
                        let remaining = key.limitRemaining ?? (limit - key.usage)
                        print(String(format: "      · %@  剩 $%.2f / $%.2f（用掉 %.0f%%）",
                                     key.name, remaining, limit, key.usage / limit * 100))
                    } else {
                        print(String(format: "      · %@  已用 $%.2f（未設上限）", key.name, key.usage))
                    }
                }
                if balance.unattributedUsage > 0.01 {
                    print(String(format: "      · 未歸戶（後台建的 key）已用 $%.2f",
                                 balance.unattributedUsage))
                }
            case .failure(let error):
                bad("\(entry.label)：\(error.localizedDescription)")
            }
        }
    }

    private static func probeHiggsfield() async {
        heading("Higgsfield")
        let found = HiggsfieldSource.candidatePaths
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) ?? "（找不到）"
        print("  CLI \(found)")
        do {
            let status = try await HiggsfieldSource.fetch()
            ok("\(status.credits) credits  ·  \(status.plan) 方案  ·  \(status.email)")
        } catch {
            bad(error.localizedDescription)
            if let hint = (error as? HiggsfieldSource.Failure)?.hint { print("    → \(hint)") }
        }
    }
}
