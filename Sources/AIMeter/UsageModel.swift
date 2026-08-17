import Foundation
import Observation
import SwiftUI

enum AlertLevel: Int, Comparable {
    case normal = 0
    case warning = 1
    case critical = 2

    static func < (lhs: AlertLevel, rhs: AlertLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// 面板上的一列。fraction 有值才畫進度條——餘額型的數字沒有「用掉幾成」的概念。
///
/// children 非空時這列可以展開（預設收起）。用在 OpenRouter：平常只看帳號餘額，
/// 想知道哪把 key 快撞到自己設的上限時才展開。
enum MetricStyle {
    /// 一般的一列。
    case row
    /// 自成一塊的分組（OpenRouter 的每個帳號）。會有自己的底色與較重的標題，
    /// 因為兩個帳號並排時，光靠列距分不出哪些 key 屬於誰。
    case group
}

struct Metric: Identifiable {
    var id: String
    var style: MetricStyle = .row
    var label: String
    /// 次要說明（重置倒數、上限、錯誤原因）。跟 label 分開存才能給不同的字級與濃度，
    /// 全部串成一行字的話層級就沒了。
    var detail: String?
    var value: String
    var fraction: Double?
    var alert: AlertLevel = .normal
    var children: [Metric] = []

    /// 子項的警戒也要往上冒泡，不然收起來的時候看不到底下有東西在燒。
    var effectiveAlert: AlertLevel {
        max(alert, children.map(\.effectiveAlert).max() ?? .normal)
    }
}

enum SourceStatus {
    case loading
    case ok
    /// 這次更新失敗，但手上還有上次成功的數字——照樣顯示，只是標明它是舊的。
    /// 把整格清空反而更糟：空白看起來像「沒事」。
    case degraded(message: String, hint: String?)
    case failed(message: String, hint: String?)
}

/// 一個來源的識別色，以及疊在它上面該用什麼顏色。
///
/// 兩個顏色一起算是必要的：Higgsfield 是螢光黃綠，白色圖示疊上去會看不見；
/// OpenRouter 是近黑色，深色圖示疊上去同樣看不見。
struct Brand {
    let color: Color
    /// 疊在 color 上的圖示顏色。
    let onColor: Color

    init(_ red: Double, _ green: Double, _ blue: Double) {
        color = Color(red: red, green: green, blue: blue)
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        onColor = luminance > 0.6
            ? Color(red: 0.08, green: 0.09, blue: 0.10)
            : .white
    }
}

@MainActor
@Observable
final class SourceBox {
    let title: String
    /// 選單列上只有形狀能用（系統的 template rendering 會吃掉顏色），
    /// 所以四個符號的輪廓要夠不一樣。
    let symbol: String
    /// 面板裡的識別色。四個灰色圖示掃起來全都一樣，顏色才是最快的線索。
    let brand: Brand
    /// 選單列上要用哪一個指標代表這個來源。
    ///
    /// Claude 指定 7 天而不是 5 小時窗：5 小時窗一直在重置，數字跳來跳去，
    /// 真正會卡住你一整週的是 7 天那條。nil 就用第一個指標。
    let headlineMetricID: String?

    var accent: Color { brand.color }

    var status: SourceStatus = .loading
    var metrics: [Metric] = []
    /// 副標，例如方案名稱或資料本身的時間戳警告。
    var note: String?
    var lastFetch: Date?
    var lastSuccess: Date?
    /// 純粹是為了讓「重新整理」按下去有反應。數字常常前後一樣，
    /// 沒有這個訊號的話使用者會以為按鈕壞了。
    var isRefreshing = false

    init(title: String, symbol: String, brand: Brand, headlineMetricID: String? = nil) {
        self.title = title
        self.symbol = symbol
        self.brand = brand
        self.headlineMetricID = headlineMetricID
    }

    var alert: AlertLevel { metrics.map(\.effectiveAlert).max() ?? .normal }

    func beginRefresh() { isRefreshing = true }

    func succeeded(metrics: [Metric], note: String?) {
        self.metrics = metrics
        self.note = note
        self.status = .ok
        self.lastFetch = Date()
        self.lastSuccess = lastFetch
        self.isRefreshing = false
    }

    func failed(_ error: Error) {
        let hint = (error as? HiggsfieldSource.Failure)?.hint
            ?? (error as? ClaudeCodeSource.Failure)?.hint
            ?? (error as? CodexSource.Failure)?.hint
        self.lastFetch = Date()
        self.isRefreshing = false

        if metrics.isEmpty {
            self.status = .failed(message: error.localizedDescription, hint: hint)
            self.note = nil
        } else {
            self.status = .degraded(message: error.localizedDescription, hint: hint)
        }
    }
}
