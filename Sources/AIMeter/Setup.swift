import Foundation

/// `AIMeter --setup`：偵測這台機器有什麼、建立設定檔、列出還缺什麼。
///
/// 刻意**非互動**。這支工具預期是由 agent 代替使用者安裝的，而 agent 沒辦法回答
/// `read -p` 那種提示——它會卡在那裡直到逾時。所以這裡只做兩件事：
/// 把能自動決定的決定掉，把只有人類能回答的**明確列出來**，讓 agent 拿去問人。
///
/// 冪等：已存在的設定檔絕不覆寫。重跑只會重新檢查並回報。
enum Setup {
    static func run() -> Never {
        AppConfig.bootstrap()
        print("\n\u{001B}[1mAI Meter 設定檢查\u{001B}[0m")

        let detected = report()
        let created = ensureConfig()
        let missing = gaps()

        print("\n設定檔 \(AppConfig.path.path(percentEncoded: false))\(created ? "（已建立）" : "（已存在，未變更）")")

        if missing.isEmpty {
            print("\n\u{001B}[1m可以安裝了。\u{001B}[0m 下一步：make install")
            if detected.contains(where: { !$0.found }) {
                print("（沒偵測到的來源已自動停用，之後裝了再跑一次 make setup 也可以）")
            }
            exit(0)
        }

        print("\n\u{001B}[1m還需要人類提供：\u{001B}[0m")
        for item in missing {
            print("\n  • \(item.question)")
            print("    為什麼：\(item.why)")
            print("    拿到之後：\(item.action)")
        }
        // 用 1 讓呼叫端（Makefile / agent）知道還沒完成，而不是靜靜地假裝成功。
        exit(1)
    }

    // MARK: 偵測

    @discardableResult
    private static func report() -> [(name: String, found: Bool, where_: String)] {
        let rows = AppConfig.detectionReport()
        print("\n偵測結果：")
        for row in rows {
            print("  \(row.found ? "✓" : "—") \(row.name.padding(toLength: 14, withPad: " ", startingAt: 0)) \(row.where_)")
        }
        return rows
    }

    /// 已存在就完全不碰——使用者自己改過的設定不該被 setup 洗掉。
    private static func ensureConfig() -> Bool {
        if FileManager.default.fileExists(atPath: AppConfig.path.path(percentEncoded: false)) {
            return false
        }
        do {
            try AppConfig.detected().save()
            return true
        } catch {
            print("\n寫入設定檔失敗：\(error.localizedDescription)")
            exit(2)
        }
    }

    // MARK: 缺什麼

    struct Gap {
        var question: String
        var why: String
        var action: String
    }

    private static func gaps() -> [Gap] {
        let config = AppConfig.load()
        var out: [Gap] = []

        if config.openRouter.enabled {
            let envPath = (config.openRouter.envFile as NSString).expandingTildeInPath
            if !FileManager.default.fileExists(atPath: envPath) {
                out.append(Gap(
                    question: "你的 OpenRouter management key 是什麼？（可以有多把，每個帳號一把）",
                    why: "查帳號餘額的 /credits 與 /analytics 都只吃 management key，一般 inference key 會 403。",
                    action: "寫進 \(envPath)，一行一把，格式 OPENROUTER_MGMT_A=sk-or-v1-…，"
                        + "然後 chmod 600。多個帳號的話在 config.json 的 openRouter.accounts 各加一筆 {label, envKey}。"
                ))
            } else {
                let env = (try? DotEnv.load(URL(fileURLWithPath: envPath))) ?? [:]
                let absent = config.openRouter.accounts.filter { (env[$0.envKey] ?? "").isEmpty }
                if !absent.isEmpty {
                    out.append(Gap(
                        question: "\(envPath) 裡缺這幾個變數：\(absent.map(\.envKey).joined(separator: "、"))，值是什麼？",
                        why: "config.json 的 accounts 有列到，但金鑰檔裡找不到對應的值。",
                        action: "補進金鑰檔，或把 config.json 裡用不到的帳號刪掉。"
                    ))
                }
            }
        }

        if config.claudeCode.enabled, ClaudeRateLimitMirror.read() == nil {
            out.append(Gap(
                question: "要不要顯示 Claude 額度的重置倒數？這需要修改你的 ~/.claude/settings.json。",
                why: "重置時間只存在於 Claude Code 餵給 statusline 的資料裡，沒有別的來源。"
                    + "不裝也能用，只是少了倒數，百分比照常顯示。",
                action: "要的話跑 make setup-statusline（會先備份、比對輸出一致才套用，不一致自動回滾）。"
            ))
        }

        return out
    }
}
