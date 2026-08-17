import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var refresher: Refresher
    @State private var launchAtLogin = LoginItem.isInstalled

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("一般") {
                LabeledContent("選單列顯示") {
                    Picker("", selection: $refresher.selection) {
                        ForEach(MenuBarSelection.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }
                Text("釘住某一源時，別的源進入 critical 仍會在選單列前面加一個記號。")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Toggle("登入時自動啟動", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        LoginItem.set(enabled: enabled)
                    }
                Text("關掉這支工具用面板右下角的電源鈕；要再打開就用 Spotlight 搜尋「AI Meter」。")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Divider()

            section("背景更新頻率") {
                Picker("", selection: $refresher.cadence) {
                    ForEach(RefreshCadence.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(refresher.cadence.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Text("不管選哪一檔，螢幕或系統睡著時都會完全停止輪詢，而且打開面板一定會抓最新的。"
                     + "所以「省電」不會讓你看到過期的數字，只是背景更新得比較少。")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            section("資料來源") {
                ForEach(SourceInfo.all) { info in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(info.title)
                            .font(.system(size: 11, weight: .medium))
                        Text(info.origin)
                            .font(.system(size: 10).monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Text("要逐項驗證數字對不對，在專案目錄跑 make probe。")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }
}

/// 設定裡那份「資料從哪來」的清單。純唯讀，是為了讓人在數字看起來不對時
/// 知道該去查哪個檔／哪支指令，不用回頭翻 README。
private struct SourceInfo: Identifiable {
    var id: String { title }
    var title: String
    var origin: String

    static var all: [SourceInfo] {
        [
            SourceInfo(
                title: "Claude Code",
                origin: ClaudeCodeSource.path.path(percentEncoded: false)
            ),
            SourceInfo(
                title: "Claude 重置時間",
                origin: ClaudeRateLimitMirror.path.path(percentEncoded: false)
            ),
            SourceInfo(
                title: "Codex",
                origin: (CodexSource.candidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
                         ?? "（找不到）") + " app-server"
            ),
            SourceInfo(
                title: "OpenRouter",
                origin: OpenRouterSource.envPath.path(percentEncoded: false)
            ),
            SourceInfo(
                title: "Higgsfield",
                origin: (HiggsfieldSource.candidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
                         ?? "（找不到）") + " account status --json"
            ),
        ]
    }
}
