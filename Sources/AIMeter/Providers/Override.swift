import Foundation

/// 用環境變數覆寫資料源位置。
///
/// 只為了測試存在：錯誤路徑（讀不到檔、金鑰壞掉、CLI 不見）必須能真的跑一次，
/// 但不該為了測它去動使用者真正的 .env 或 Claude 的資料檔。
enum Override {
    static func path(_ name: String) -> String? {
        guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else { return nil }
        return (value as NSString).expandingTildeInPath
    }

    static func url(_ name: String) -> URL? {
        path(name).map { URL(fileURLWithPath: $0) }
    }
}
