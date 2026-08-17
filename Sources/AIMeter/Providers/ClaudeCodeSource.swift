import Foundation

/// Claude 訂閱額度。
///
/// 資料來自 Claude 桌面 App 寫的 plan-usage-history.json，格式：
///   { version: 2, samples: [ { t: <epoch ms>, org: <uuid>, u: { fh, sd, xu } } ] }
/// fh = 五小時窗用量 %、sd = 七天用量 %、xu = 超額用量 %（沒超額時通常整個欄位不存在）。
///
/// 刻意不去解析 ~/.claude/projects 底下那 1.3 GB 的 jsonl：那條路要做增量 tail
/// 加上依 message.id 去重（同一次回應會重複寫約 3.2 倍），換來的只是花費推估，
/// 而訂閱制真正可行動的數字是這裡的百分比。
struct ClaudeUsage {
    var fiveHour: Int
    var sevenDay: Int
    var extraUsage: Int?
    var sampledAt: Date

    /// 這個檔只在 Claude 桌面 App 執行時才更新，所以「檔案有讀到」不等於「數字是現在的」。
    var age: TimeInterval { Date().timeIntervalSince(sampledAt) }
    var isStale: Bool { age > 15 * 60 }
}

enum ClaudeCodeSource {
    /// 可用 AIMETER_CLAUDE_HISTORY 覆寫，方便測壞掉的情況而不用去動真的檔案。
    static var path: URL {
        Override.url("AIMETER_CLAUDE_HISTORY")
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Application Support/Claude/plan-usage-history.json")
    }

    enum Failure: LocalizedError {
        case missingFile
        case malformed
        case empty

        var errorDescription: String? {
            switch self {
            case .missingFile:
                return "找不到 plan-usage-history.json"
            case .malformed:
                return "plan-usage-history.json 格式不符預期"
            case .empty:
                return "檔案裡沒有任何用量樣本"
            }
        }

        var hint: String? {
            switch self {
            case .missingFile:
                return "這個檔由 Claude 桌面 App 產生，先開一次 Claude.app"
            case .malformed:
                // 這個檔的格式是 Claude 桌面 App 的內部實作，沒有相容性承諾，
                // 改版改掉是完全可能的事。講清楚比讓人以為自己弄壞了好。
                return "可能是 Claude.app 改了格式，需要更新這支工具"
            case .empty:
                return nil
            }
        }
    }

    private struct Payload: Decodable {
        struct Sample: Decodable {
            struct Usage: Decodable {
                var fh: Int?
                var sd: Int?
                var xu: Int?
            }
            var t: Double
            var u: Usage
        }
        var samples: [Sample]
    }

    /// 只在檔案 mtime 變動時重新解析——檔案 412 KB、每 5 分鐘才多一筆，
    /// 每 60 秒重解一次是白費力氣。
    private static var cache: (mtime: Date, usage: ClaudeUsage)?

    static func read() throws -> ClaudeUsage {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path.path(percentEncoded: false))
        guard let attrs, let mtime = attrs[.modificationDate] as? Date else {
            throw Failure.missingFile
        }
        if let cache, cache.mtime == mtime { return cache.usage }

        guard let data = try? Data(contentsOf: path),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else {
            throw Failure.malformed
        }

        // 理論上是時序寫入的，但拿最大的 t 比拿最後一筆穩。
        guard let latest = payload.samples.max(by: { $0.t < $1.t }) else { throw Failure.empty }

        let usage = ClaudeUsage(
            fiveHour: latest.u.fh ?? 0,
            sevenDay: latest.u.sd ?? 0,
            extraUsage: latest.u.xu,
            sampledAt: Date(timeIntervalSince1970: latest.t / 1000)
        )
        cache = (mtime, usage)
        return usage
    }
}
