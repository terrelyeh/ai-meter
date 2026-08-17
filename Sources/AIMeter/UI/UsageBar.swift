import SwiftUI

extension AlertLevel {
    var tint: Color {
        switch self {
        case .normal: return Color(red: 0.20, green: 0.72, blue: 0.45)
        case .warning: return Color(red: 0.95, green: 0.64, blue: 0.15)
        case .critical: return Color(red: 0.91, green: 0.31, blue: 0.28)
        }
    }
}

/// 一條進度條。只有「用掉幾成」有意義的指標才會拿到 fraction。
struct UsageBar: View {
    var fraction: Double
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.09))
                Capsule()
                    .fill(tint)
                    .frame(width: max(3, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 6)
    }
}

/// 面板裡的一列。層級是：名稱（主）→ 數值（主、右對齊）→ 說明（次）→ 進度條。
/// 有 children 就可以點開，預設收起。
struct MetricRow: View {
    var metric: Metric
    var isExpanded: Bool = false
    var accent: Color = .accentColor
    var onToggle: (() -> Void)?

    private var expandable: Bool { !metric.children.isEmpty }
    private var isGroup: Bool { metric.style == .group }

    var body: some View {
        if isGroup {
            grouped
        } else {
            plain
        }
    }

    /// 分組（例如 OpenRouter 的一個帳號）：自己的底色 + 左側色條。
    /// 兩個帳號各自成塊，就不會分不出哪些 key 是誰的。
    private var grouped: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(accent.opacity(0.55))
                .frame(width: 2.5)
            plain
                .padding(.leading, 8)
                .padding(.trailing, 8)
                .padding(.vertical, 7)
        }
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var plain: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            if let detail = metric.detail {
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, expandable ? 12 : 0)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let fraction = metric.fraction {
                UsageBar(fraction: fraction, tint: metric.alert.tint)
                    .padding(.leading, expandable ? 12 : 0)
            }
            if expandable && isExpanded {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(metric.children) { child in
                        MetricRow(metric: child)
                    }
                }
                .padding(.leading, 14)
                .padding(.top, 4)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if expandable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 8)
            }
            Text(metric.label)
                .font(.system(size: isGroup ? 12 : 11.5, weight: isGroup ? .semibold : .regular))
                .foregroundStyle(.primary.opacity(isGroup ? 1 : 0.85))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text(metric.value)
                .font(.system(size: isGroup ? 12 : 11.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(metric.alert == .normal ? Color.primary : metric.alert.tint)
        }
        .contentShape(Rectangle())
        .onTapGesture { if expandable { onToggle?() } }
    }
}
