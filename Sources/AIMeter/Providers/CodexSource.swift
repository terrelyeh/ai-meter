import Foundation

struct CodexWindow: Identifiable {
    var usedPercent: Double
    var windowMinutes: Int
    var resetsAt: Date?

    var id: String { "\(windowMinutes)" }

    /// 視窗長度不要寫死成「5 小時 / 每週」。不同方案的視窗不一樣——
    /// 這個帳號 (prolite) 只有一個 10080 分鐘的窗，根本沒有 5 小時窗。
    var label: String {
        if windowMinutes % 1440 == 0 { return "\(windowMinutes / 1440) 天" }
        if windowMinutes >= 60 { return "\(windowMinutes / 60) 小時窗" }
        return "\(windowMinutes) 分鐘窗"
    }

    var timeUntilReset: TimeInterval? {
        guard let resetsAt else { return nil }
        let remaining = resetsAt.timeIntervalSinceNow
        return remaining > 0 ? remaining : nil
    }
}

struct CodexStatus {
    var windows: [CodexWindow]
    var planType: String?
    var creditBalance: String?
    var hasCredits: Bool
}

/// Codex 額度。
///
/// 使用者跑的是 ChatGPT 桌面 App，不是 npm 的 codex CLI（那支的 vendored binary 是壞的）。
/// App 內附一支能用的 Rust binary，用 JSON-RPC over stdio 說話：
///
///   codex app-server
///   → initialize / initialized / account/rateLimits/read
///
/// 它跟 App 共用 ~/.codex/auth.json，所以 token 更新不用我們管。
/// 這也是為什麼不直接拿 auth.json 裡的 JWT 去打 OpenAI 後端——那樣要自己處理換發與過期。
enum CodexSource {
    static var candidatePaths: [String] {
        if let override = Override.path("AIMETER_CODEX_BIN") { return [override] }
        return [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "\(NSHomeDirectory())/Applications/ChatGPT.app/Contents/Resources/codex",
        ]
    }

    /// 只呼叫唯讀的方法。account/rateLimitResetCredit/consume 會花掉一張重置額度、
    /// account/logout 會把人登出——那些絕對不能碰。
    private static let readOnlyMethod = "account/rateLimits/read"
    private static let timeout: TimeInterval = 20

    enum Failure: LocalizedError {
        case notInstalled
        case noResponse
        case badOutput

        var errorDescription: String? {
            switch self {
            case .notInstalled: return "找不到 ChatGPT.app 裡的 codex"
            case .noResponse: return "codex app-server 沒有回應"
            case .badOutput: return "codex 回應格式不符預期"
            }
        }

        var hint: String? {
            switch self {
            case .notInstalled: return "需要安裝 ChatGPT 桌面 App"
            case .noResponse, .badOutput: return "ChatGPT App 可能需要重新登入"
            }
        }

        var isTransient: Bool {
            if case .noResponse = self { return true }
            return false
        }
    }

    // MARK: 回應解析

    private struct Response: Decodable {
        struct Result: Decodable {
            var rateLimits: RateLimits?
        }
        struct RateLimits: Decodable {
            var primary: Window?
            var secondary: Window?
            var credits: Credits?
            var planType: String?
        }
        struct Window: Decodable {
            var usedPercent: Double?
            var windowDurationMins: Int?
            var resetsAt: Double?
        }
        struct Credits: Decodable {
            var hasCredits: Bool?
            var balance: String?
        }
        var id: Int?
        var result: Result?
    }

    static func fetch() async throws -> CodexStatus {
        guard let executable = candidatePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw Failure.notInstalled
        }
        let payload = try query(executable: executable)

        guard let limits = payload.result?.rateLimits else { throw Failure.badOutput }

        let windows = [limits.primary, limits.secondary]
            .compactMap { $0 }
            .compactMap { window -> CodexWindow? in
                guard let used = window.usedPercent, let minutes = window.windowDurationMins else { return nil }
                return CodexWindow(
                    usedPercent: used,
                    windowMinutes: minutes,
                    resetsAt: window.resetsAt.map { Date(timeIntervalSince1970: $0) }
                )
            }
        guard !windows.isEmpty else { throw Failure.badOutput }

        return CodexStatus(
            windows: windows,
            planType: limits.planType,
            creditBalance: limits.credits?.balance,
            hasCredits: limits.credits?.hasCredits ?? false
        )
    }

    // MARK: JSON-RPC over stdio

    private static func query(executable: String) throws -> Response {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server"]

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        try process.run()

        // 看門狗：沒有它的話，下面的 availableData 會在對方不回話時永遠卡住。
        // 殺掉程序會讓讀取端收到 EOF，迴圈才有辦法結束。
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        defer {
            watchdog.cancel()
            if process.isRunning { process.terminate() }
        }

        let writer = input.fileHandleForWriting
        var reader = LineReader(handle: output.fileHandleForReading)

        // 握手順序不能省。三行一次灌進去的話伺服器不會回 —— 實測會收到三行輸出
        // 但裡面沒有我們要的那一則。必須等 initialize 回來才送後面兩行。
        writer.write(Data((Request.initialize + "\n").utf8))
        guard awaitResponse(id: 0, from: &reader) != nil else { throw Failure.noResponse }

        writer.write(Data((Request.initialized + "\n").utf8))
        writer.write(Data((Request.rateLimits(method: readOnlyMethod) + "\n").utf8))
        guard let response = awaitResponse(id: 1, from: &reader) else { throw Failure.noResponse }

        return response
    }

    /// 一直讀到指定 id 的回應為止。中間會夾雜 remoteControl/status/changed 之類的
    /// 通知（沒有 id），直接跳過。回 nil 代表 EOF——程序結束或被看門狗殺掉。
    private static func awaitResponse(id: Int, from reader: inout LineReader) -> Response? {
        while let line = reader.next() {
            guard let response = try? JSONDecoder().decode(Response.self, from: line) else { continue }
            if response.id == id { return response }
        }
        return nil
    }

    private struct LineReader {
        let handle: FileHandle
        private var buffer = Data()

        init(handle: FileHandle) { self.handle = handle }

        mutating func next() -> Data? {
            while true {
                if let newline = buffer.firstIndex(of: 0x0A) {
                    let line = Data(buffer[buffer.startIndex..<newline])
                    buffer.removeSubrange(buffer.startIndex...newline)
                    return line
                }
                let chunk = handle.availableData
                if chunk.isEmpty { return nil }
                buffer.append(chunk)
            }
        }
    }

    private enum Request {
        static let initialize =
            #"{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"clientInfo":{"name":"aimeter","title":"AI Meter","version":"1.0"}}}"#
        static let initialized =
            #"{"jsonrpc":"2.0","method":"initialized","params":{}}"#
        static func rateLimits(method: String) -> String {
            #"{"jsonrpc":"2.0","id":1,"method":"\#(method)","params":{}}"#
        }
    }
}
