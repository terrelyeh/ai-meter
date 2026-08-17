import Foundation

struct HiggsfieldStatus {
    var credits: Int
    var plan: String
    var email: String
}

/// Higgsfield credits。
///
/// 官方 API docs 只有送件 / 查狀態 / 取消，沒有餘額端點；但本機裝的 CLI
/// (@higgsfield/cli) 有 `account status --json`，直接吐 {credits, email, subscription_plan_type}。
///
/// 用絕對路徑而不是靠 PATH：從 LaunchAgent 啟動時 PATH 只有系統預設值，找不到 Homebrew。
enum HiggsfieldSource {
    static var candidatePaths: [String] {
        if let override = Override.path("AIMETER_HIGGSFIELD_BIN") { return [override] }
        return [
            "/opt/homebrew/bin/higgsfield",
            "/usr/local/bin/higgsfield",
        ]
    }

    enum Failure: LocalizedError {
        case notInstalled
        /// PATH 上找不到 node。這支 CLI 是 Node 腳本，沒有 node 就跑不起來——
        /// 跟憑證過期同樣必須分開講，不然使用者會去重登一個根本沒壞的帳號。
        case missingRuntime
        /// 服務層沒回應。實測這支 CLI 大約每五次會抖一次，
        /// 跟憑證過期必須分開講——不然使用者會被叫去重登一個根本沒壞的帳號。
        case unreachable
        case commandFailed(status: Int32, output: String)
        case badOutput

        var errorDescription: String? {
            switch self {
            case .notInstalled:
                return "找不到 higgsfield CLI"
            case .missingRuntime:
                return "執行 higgsfield 需要的 node 找不到"
            case .unreachable:
                return "Higgsfield 服務暫時無回應"
            case .commandFailed(let status, let output):
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "CLI 以狀態碼 \(status) 結束" : String(trimmed.prefix(160))
            case .badOutput:
                return "CLI 輸出不是預期的 JSON"
            }
        }

        /// 憑證過期跟餘額歸零在畫面上長得一樣，但意思完全相反——
        /// 所以失敗時一定要給出可執行的下一步，不能只顯示 0。
        var hint: String? {
            switch self {
            case .notInstalled:
                return "npm i -g @higgsfield/cli"
            case .missingRuntime:
                return "把 node 所在的 bin 目錄加進 PATH，或重裝 CLI 讓它與 node 同目錄"
            case .unreachable:
                return nil          // 自己會好，不要叫人去做任何事
            case .commandFailed, .badOutput:
                return "憑證可能過期了，跑 higgsfield auth login"
            }
        }

        /// 這種錯誤下次再試就好，不值得驚動使用者。
        var isTransient: Bool {
            if case .unreachable = self { return true }
            return false
        }
    }

    /// 這支 CLI 是 Node 腳本（shebang `#!/usr/bin/env node`），所以跑它需要 PATH 上有 node。
    ///
    /// 從終端機執行沒問題，但 app 由 Finder 或 LaunchAgent 啟動時 PATH 只有系統最小預設值，
    /// `env node` 就會失敗。這也是為什麼 `make probe` 過了不代表 app 沒事——
    /// probe 繼承的是你 shell 的 PATH，app 沒有。
    ///
    /// 解法：沿著符號連結一層一層走，把每一層所在的目錄都加進 PATH。
    /// npm 安裝的 CLI 幾乎都跟執行它的 node 放在同一個 bin 目錄
    ///（這台機器上 higgsfield 與 node 都在 ~/.hermes/node/bin）。
    private static func searchPath(for executable: String) -> String {
        var dirs: [String] = []
        var current = executable

        for _ in 0..<8 {                       // 上限只是避免壞掉的循環連結
            let dir = (current as NSString).deletingLastPathComponent
            if !dir.isEmpty, !dirs.contains(dir) { dirs.append(dir) }

            guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: current)
            else { break }
            current = target.hasPrefix("/")
                ? target
                : (dir as NSString).appendingPathComponent(target)
        }

        dirs += ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        if let inherited = ProcessInfo.processInfo.environment["PATH"] { dirs.append(inherited) }
        return dirs.joined(separator: ":")
    }

    /// `env: node: No such file or directory`
    private static let runtimeMarkers = [
        "env: node",
        "node: No such file",
        "env: node:",
    ]

    /// 實測看到的抖動訊息長這樣：`Error: request failed (no response received)`
    private static let transientMarkers = [
        "no response received",
        "request failed",
        "timeout",
        "connection reset",
        "EAI_AGAIN",
    ]

    private struct Payload: Decodable {
        var credits: Int
        var email: String
        var subscription_plan_type: String
    }

    /// CLI 對後端的呼叫會偶發失敗（實測 5 次中 1 次），所以短時間內重試幾次，
    /// 免得一次抖動就讓面板上的數字消失。
    static func fetch(attempts: Int = 3) async throws -> HiggsfieldStatus {
        var lastError: Error = Failure.unreachable
        for attempt in 1...max(attempts, 1) {
            do {
                return try runOnce()
            } catch let error as Failure where error.isTransient {
                lastError = error
                if attempt < attempts { try? await Task.sleep(for: .seconds(2)) }
            }
        }
        throw lastError
    }

    private static func runOnce() throws -> HiggsfieldStatus {
        guard let executable = candidatePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw Failure.notInstalled
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["account", "status", "--json"]
        process.environment = ProcessInfo.processInfo.environment
            .merging(["PATH": searchPath(for: executable)]) { _, new in new }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        // 先讀完再 wait，避免 pipe 緩衝滿了互相卡死。
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            // 這支 CLI 把錯誤印在哪一條管線並不固定，兩條都看。
            let stderrText = String(data: errData, encoding: .utf8) ?? ""
            let stdoutText = String(data: outData, encoding: .utf8) ?? ""
            let combined = stderrText.isEmpty ? stdoutText : stderrText

            if Self.runtimeMarkers.contains(where: { combined.localizedCaseInsensitiveContains($0) }) {
                throw Failure.missingRuntime
            }
            if Self.transientMarkers.contains(where: { combined.localizedCaseInsensitiveContains($0) }) {
                throw Failure.unreachable
            }
            throw Failure.commandFailed(status: process.terminationStatus, output: combined)
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: outData) else {
            throw Failure.badOutput
        }

        return HiggsfieldStatus(
            credits: payload.credits,
            plan: payload.subscription_plan_type,
            email: payload.email
        )
    }
}
