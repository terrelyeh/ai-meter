import Foundation

/// 背景更新頻率。
///
/// 用具名的三檔而不是四個各自可調的秒數：各來源的成本差很多
/// （Claude 是讀本機小檔，Codex 每次要起一支 219 MB 的 binary），
/// 讓使用者逐項調很容易調出一組又慢又耗電的組合。
enum RefreshCadence: String, CaseIterable, Identifiable {
    case powerSaver
    case standard
    case eager

    var id: String { rawValue }

    var title: String {
        switch self {
        case .powerSaver: return "省電"
        case .standard: return "標準"
        case .eager: return "積極"
        }
    }

    var detail: String {
        switch self {
        case .powerSaver: return "Claude 5 分鐘，其餘 30～60 分鐘"
        case .standard: return "Claude 1 分鐘，其餘 15～30 分鐘"
        case .eager: return "Claude 30 秒，其餘 5～10 分鐘"
        }
    }

    /// 秒。順序：Claude / Codex / OpenRouter / Higgsfield。
    var intervals: (claude: UInt64, codex: UInt64, openRouter: UInt64, higgsfield: UInt64) {
        switch self {
        case .powerSaver: return (300, 1800, 1800, 3600)
        case .standard: return (60, 900, 900, 1800)
        case .eager: return (30, 300, 300, 600)
        }
    }

    private static let key = "refreshCadence"

    static var stored: RefreshCadence {
        get { RefreshCadence(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .standard }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}
