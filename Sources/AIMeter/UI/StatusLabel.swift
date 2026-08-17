import AppKit
import SwiftUI

/// 選單列上那一小塊。空間只夠放一個數字，所以放「現在最該知道的那一個」。
struct StatusLabel: View {
    var headline: Refresher.Headline

    var body: some View {
        // spacing 設 0：選單列不見得會照 HStack 的 spacing 排，
        // 所以徽章與數字之間的留白直接畫進圖片裡（見 MenuBarBadge.gap），
        // 那樣間距才是可控的。
        HStack(spacing: 0) {
            // 永遠顯示該來源自己的徽章。
            //
            // 之前警戒時會把圖示換成驚嘆號三角形，但那讓「我明明選了 Codex，
            // 卻看到一個三角形」——使用者是刻意釘住某一源的，換掉圖示等於
            // 把他的選擇蓋掉。而且嚴重程度本來就寫在旁邊的百分比裡了。
            Image(nsImage: MenuBarBadge.image(for: headline))

            Text(headline.text)
                .monospacedDigit()

            // 只有「別的來源」出事才加記號——那是畫面上看不到的資訊，
            // 不標出來就等於藏起來。自己這一源的狀態看數字就知道。
            if headline.otherCritical {
                Image(systemName: "exclamationmark.circle.fill")
                    .padding(.leading, 4)
            }
        }
    }
}

/// 把徽章畫成一張 NSImage 交給選單列。
///
/// 直接用 `Image(systemName:)` 的話，系統會以 template 模式繪製——整個壓成單色，
/// 底色會被丟掉。改成自己算好圖並把 `isTemplate` 設為 false，顏色才留得住。
@MainActor
enum MenuBarBadge {
    private static var cache: [String: NSImage] = [:]

    static func image(for headline: Refresher.Headline) -> NSImage {
        if let hit = cache[headline.symbol] { return hit }
        let rendered = render(headline)
        cache[headline.symbol] = rendered
        return rendered
    }

    private static func render(_ headline: Refresher.Headline) -> NSImage {
        // 選單列高度約 22pt，18 是不會被系統縮放又看得清楚的上限附近。
        let side: CGFloat = 18
        // 徽章右側的留白，直接算進圖裡。
        let gap: CGFloat = 7

        let badge = RoundedRectangle(cornerRadius: 4.5, style: .continuous)
            .fill(headline.brand.color)
            .frame(width: side, height: side)
            .overlay(
                Image(systemName: headline.symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(headline.brand.onColor)
            )
            .overlay(
                // 深色選單列配上近黑色徽章會整塊消失。這裡不能用 Color.primary——
                // 它跟著 app 的配色走，不見得跟選單列一致——所以固定用半透明白。
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
            )
            .padding(.trailing, gap)

        let renderer = ImageRenderer(content: badge)
        renderer.scale = 2                       // 視網膜螢幕不要糊掉
        guard let image = renderer.nsImage else { return NSImage() }

        // 關鍵：template 會把顏色壓掉，正是我們要避免的。
        image.isTemplate = false
        return image
    }
}
