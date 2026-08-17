import SwiftUI

/// 選單列上那一小塊。空間只夠放一個數字，所以放「現在最該知道的那一個」。
struct StatusLabel: View {
    var headline: Refresher.Headline

    var body: some View {
        HStack(spacing: 3) {
            // 釘住某一源時仍然顯示它自己的圖示——不然「我選了 Claude 卻看到別的東西」
            // 會很困惑。但別的源出事還是要有記號，不能靜靜地藏起來。
            if headline.otherCritical {
                Image(systemName: "exclamationmark.circle.fill")
            }
            // 選單列的著色會被系統的 template rendering 吃掉，
            // 光靠顏色分辨不可靠，形狀才靠得住。
            Image(systemName: headline.alert > .normal ? "exclamationmark.triangle.fill" : headline.symbol)
            Text(headline.text)
                .monospacedDigit()
        }
    }
}
