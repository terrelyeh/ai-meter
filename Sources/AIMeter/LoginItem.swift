import Foundation

/// 開機自動啟動。
///
/// 走 LaunchAgent 而不是 SMAppService：這支 app 是 ad-hoc 簽章（沒有開發者憑證），
/// SMAppService 在那種情況下註冊不保證會成立，而 LaunchAgent 只是一個 plist。
enum LoginItem {
    static let label = "com.terrelyeh.aimeter"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/LaunchAgents/\(label).plist")
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path(percentEncoded: false))
    }

    static func set(enabled: Bool) {
        enabled ? install() : remove()
    }

    private static func install() {
        guard let executable = Bundle.main.executableURL else { return }

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable.path(percentEncoded: false)],
            "RunAtLoad": true,
            // 崩潰時別無限重啟，登入時跑一次就好。
            "KeepAlive": false,
        ]

        do {
            try FileManager.default.createDirectory(
                at: plistURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL)
            launchctl(["bootout", "gui/\(getuid())/\(label)"])   // 先清掉舊的註冊
            launchctl(["bootstrap", "gui/\(getuid())", plistURL.path(percentEncoded: false)])
        } catch {
            NSLog("[AIMeter] 寫入 LaunchAgent 失敗: \(error)")
        }
    }

    private static func remove() {
        launchctl(["bootout", "gui/\(getuid())/\(label)"])
        try? FileManager.default.removeItem(at: plistURL)
    }

    @discardableResult
    private static func launchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
