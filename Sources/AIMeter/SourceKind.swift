import Foundation

/// 四個來源的識別。
///
/// 有這個 enum 之前，「對每個來源做一件事」都是一條四行的 if 串
/// （建迴圈、收集 boxes、手動重整、面板打開時重抓……），
/// 每加一個地方就多抄一份，漏掉哪一個不會有編譯錯誤。
enum SourceKind: String, CaseIterable, Identifiable {
    case claudeCode
    case codex
    case openRouter
    case higgsfield

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .openRouter: return "OpenRouter"
        case .higgsfield: return "Higgsfield"
        }
    }
}

extension AppConfig {
    func enabled(_ kind: SourceKind) -> Bool {
        switch kind {
        case .claudeCode: return claudeCode.enabled
        case .codex: return codex.enabled
        case .openRouter: return openRouter.enabled
        case .higgsfield: return higgsfield.enabled
        }
    }

    mutating func setEnabled(_ value: Bool, for kind: SourceKind) {
        switch kind {
        case .claudeCode: claudeCode.enabled = value
        case .codex: codex.enabled = value
        case .openRouter: openRouter.enabled = value
        case .higgsfield: higgsfield.enabled = value
        }
    }
}

extension RefreshCadence {
    func interval(for kind: SourceKind) -> UInt64 {
        switch kind {
        case .claudeCode: return intervals.claude
        case .codex: return intervals.codex
        case .openRouter: return intervals.openRouter
        case .higgsfield: return intervals.higgsfield
        }
    }

    /// 面板打開時的重抓門檻。便宜的可以抓得勤一點，
    /// 要 fork 程序的就別因為連開兩次面板而跑兩次。
    func openThreshold(for kind: SourceKind) -> TimeInterval {
        switch kind {
        case .claudeCode: return 30
        case .codex, .openRouter: return 120
        case .higgsfield: return 300
        }
    }
}
