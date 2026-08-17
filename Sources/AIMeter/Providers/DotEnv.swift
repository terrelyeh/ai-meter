import Foundation

/// 極簡 .env 讀取。只夠用來把金鑰從設定指定的 .env 撈出來，
/// 不打算支援變數展開、多行值那些 dotenv 方言。
enum DotEnv {
    enum Failure: LocalizedError {
        case unreadable(URL)
        case missingKey(String, URL)

        var errorDescription: String? {
            switch self {
            case .unreadable(let url):
                return "讀不到 \(url.path)"
            case .missingKey(let key, let url):
                return "\(url.lastPathComponent) 裡沒有 \(key)"
            }
        }
    }

    static func load(_ url: URL) throws -> [String: String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw Failure.unreadable(url)
        }

        var out: [String: String] = [:]
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if line.hasPrefix("export ") { line = String(line.dropFirst("export ".count)) }

            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)

            // 去掉成對的引號；沒引號的話順手切掉行末註解。
            if value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first {
                value = String(value.dropFirst().dropLast())
            } else if let hash = value.firstIndex(of: "#") {
                value = value[..<hash].trimmingCharacters(in: .whitespaces)
            }

            guard !key.isEmpty else { continue }
            out[key] = value
        }
        return out
    }

    static func value(_ key: String, in url: URL) throws -> String {
        let env = try load(url)
        guard let v = env[key], !v.isEmpty else { throw Failure.missingKey(key, url) }
        return v
    }
}
