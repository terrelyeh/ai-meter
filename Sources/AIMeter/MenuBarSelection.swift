import Foundation

/// 選單列上要顯示哪一個來源。
///
/// 預設 `.auto`：平常顯示 Claude 的 5 小時窗，任一源進入警戒就換成那一個。
/// 但「今天我就是想盯 OpenRouter」是完全合理的需求，所以可以釘住。
enum MenuBarSelection: String, CaseIterable, Identifiable {
    case auto
    case claude
    case codex
    case openRouter
    case higgsfield

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "自動（最緊要的）"
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .openRouter: return "OpenRouter"
        case .higgsfield: return "Higgsfield"
        }
    }

    private static let key = "menuBarSelection"

    static var stored: MenuBarSelection {
        get { MenuBarSelection(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .auto }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}
