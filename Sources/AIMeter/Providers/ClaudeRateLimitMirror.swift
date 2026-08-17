import Foundation

/// 額度的「重置時間」。
///
/// plan-usage-history.json 只有百分比、沒有重置時間。resets_at 只存在於 Claude Code
/// 餵給 statusline 的 payload 裡，而那份 payload 只在 session 執行時才出現。
/// 所以 ~/.claude/statusline-mirror.sh 這層 wrapper 會把它鏡射到這個檔，我們讀鏡射檔。
///
/// 讀不到不是錯誤——只是還沒有任何 Claude Code session 跑過 statusline。
/// 那種情況下百分比照顯示，只是沒有倒數。
struct RateLimitWindow {
    var usedPercentage: Int?
    var resetsAt: Date?

    /// 已經過了重置時間就別再倒數——顯示一個負的或停住的時間比不顯示更糟。
    var timeUntilReset: TimeInterval? {
        guard let resetsAt else { return nil }
        let remaining = resetsAt.timeIntervalSinceNow
        return remaining > 0 ? remaining : nil
    }
}

struct RateLimitMirror {
    var fiveHour: RateLimitWindow
    var sevenDay: RateLimitWindow
    var capturedAt: Date
}

enum ClaudeRateLimitMirror {
    static var path: URL {
        Override.url("AIMETER_RATE_LIMIT_MIRROR")
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appending(path: ".claude/rate-limits.json")
    }

    /// resets_at 的型別沒有文件保證：statusline 腳本把它當 epoch 秒數在算，
    /// 但 payload 也可能是 ISO 字串。兩種都接，猜錯不會讓整格壞掉。
    private struct Window: Decodable {
        var used_percentage: Int?
        var resets_at: FlexibleDate?
    }

    private struct Payload: Decodable {
        var five_hour: Window?
        var seven_day: Window?
        var captured_at: Double?
    }

    private struct FlexibleDate: Decodable {
        var date: Date?

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()

            if let number = try? container.decode(Double.self) {
                // 一般是秒；超過這個量級就是毫秒。
                date = Date(timeIntervalSince1970: number > 1e12 ? number / 1000 : number)
                return
            }
            if let text = try? container.decode(String.self) {
                date = ISO8601DateFormatter.parse(text)
                return
            }
            date = nil
        }
    }

    /// 沒有鏡射檔就回 nil，呼叫端當「這次沒有倒數資訊」處理即可。
    static func read() -> RateLimitMirror? {
        guard let data = try? Data(contentsOf: path),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { return nil }

        return RateLimitMirror(
            fiveHour: RateLimitWindow(
                usedPercentage: payload.five_hour?.used_percentage,
                resetsAt: payload.five_hour?.resets_at?.date
            ),
            sevenDay: RateLimitWindow(
                usedPercentage: payload.seven_day?.used_percentage,
                resetsAt: payload.seven_day?.resets_at?.date
            ),
            capturedAt: Date(timeIntervalSince1970: payload.captured_at ?? 0)
        )
    }
}

private extension ISO8601DateFormatter {
    static func parse(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
