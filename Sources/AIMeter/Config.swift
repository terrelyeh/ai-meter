import Foundation

/// 使用者設定。
///
/// 存在的理由：金鑰位置、帳號標籤、要開哪些來源，這些都是**資料**，
/// 但原本活在 Swift 程式碼裡。搬出來之後別人才可能裝得起來——
/// 否則他 clone 下去第一件事就是要改 source code。
struct AppConfig: Codable {
    var openRouter = OpenRouter()
    var claudeCode = Toggle()
    var codex = Toggle()
    var higgsfield = Toggle()

    struct Toggle: Codable {
        var enabled = true
    }

    struct OpenRouter: Codable {
        var enabled = true
        /// 讀金鑰的 .env 檔。之所以指向別的檔而不是把金鑰抄進來，
        /// 是為了不要讓同一把金鑰在硬碟上出現兩份。
        var envFile = "~/.config/ai-meter/openrouter.env"
        var accounts: [Account] = [Account(label: "個人", envKey: "OPENROUTER_MGMT_A")]

        struct Account: Codable {
            var label: String
            var envKey: String
        }
    }

    // MARK: 位置

    static var path: URL {
        Override.url("AIMETER_CONFIG")
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appending(path: ".config/ai-meter/config.json")
    }

    // MARK: 讀寫

    /// 載入設定並套用到各 provider。
    ///
    /// UI、--setup、--probe 是三個各自獨立的進入點，三邊都得先做這件事——
    /// 少做的那一邊會拿著預設值跑，然後回報一個跟實際不符的結果。
    @discardableResult
    static func bootstrap() -> AppConfig {
        let config = load()
        OpenRouterSource.config = config.openRouter
        return config
    }

    /// 讀不到或壞掉都不是致命錯誤——用偵測到的預設值跑，
    /// 因為「設定檔有問題」不該讓整個工具開不起來。
    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: path),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data)
        else { return detected() }
        return config
    }

    func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        let url = Self.path
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(self).write(to: url)
    }

    // MARK: 自動偵測

    /// 首次啟動時依「這台機器上實際裝了什麼」決定預設開哪些。
    ///
    /// 沒裝 ≠ 壞掉。同事沒裝 Higgsfield 卻看到一格紅字錯誤，那是錯的訊息——
    /// 該有的行為是那一格根本不存在。
    static func detected() -> AppConfig {
        var config = AppConfig()
        config.claudeCode.enabled = FileManager.default.fileExists(
            atPath: ClaudeCodeSource.path.path(percentEncoded: false)
        )
        config.codex.enabled = CodexSource.candidatePaths.contains {
            FileManager.default.isExecutableFile(atPath: $0)
        }
        config.higgsfield.enabled = HiggsfieldSource.candidatePaths.contains {
            FileManager.default.isExecutableFile(atPath: $0)
        }
        // OpenRouter 沒有「裝了沒」可以偵測，只能看金鑰檔在不在。
        config.openRouter.enabled = FileManager.default.fileExists(
            atPath: (config.openRouter.envFile as NSString).expandingTildeInPath
        )
        return config
    }

    /// 偵測結果的人話版本，給 `make setup` 印出來。
    static func detectionReport() -> [(name: String, found: Bool, where_: String)] {
        let fm = FileManager.default
        let codex = CodexSource.candidatePaths.first { fm.isExecutableFile(atPath: $0) }
        let higgsfield = HiggsfieldSource.candidatePaths.first { fm.isExecutableFile(atPath: $0) }
        let claudePath = ClaudeCodeSource.path.path(percentEncoded: false)
        let envPath = OpenRouterSource.envPath.path(percentEncoded: false)

        return [
            ("Claude Code", fm.fileExists(atPath: claudePath), claudePath),
            ("Codex", codex != nil, codex ?? CodexSource.candidatePaths[0]),
            ("Higgsfield", higgsfield != nil, higgsfield ?? HiggsfieldSource.candidatePaths[0]),
            ("OpenRouter", fm.fileExists(atPath: envPath), envPath),
        ]
    }
}
