import Foundation

/// 選單列項目要多寬。
///
/// 選單列的空間是固定的，而每個人塞了多少東西差很多——圖示一多，
/// 排在後面的項目會直接不被畫出來（app 還在跑，只是看不到）。
/// 所以寬度必須讓使用者自己決定，不能由這支工具單方面佔位。
enum MenuBarStyle: String, CaseIterable, Identifiable {
    case badgeAndValue
    case valueOnly
    case badgeOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .badgeAndValue: return "徽章 + 數字"
        case .valueOnly: return "只顯示數字"
        case .badgeOnly: return "只顯示徽章"
        }
    }

    var showsBadge: Bool { self != .valueOnly }
    var showsValue: Bool { self != .badgeOnly }

    /// 徽章右邊要留多少白。只剩徽章時不需要留，那 7pt 是給數字用的。
    var gap: Double { showsValue ? 7 : 0 }

    private static let key = "menuBarStyle"

    static var stored: MenuBarStyle {
        get { MenuBarStyle(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .badgeAndValue }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}
