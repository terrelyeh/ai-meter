import Foundation

struct OpenRouterKey {
    var name: String
    var usage: Double
    /// 沒設上限的 key 就是 nil——那是「沒有預算界線」，不是「上限為 0」。
    var limit: Double?
    var limitRemaining: Double?
}

struct OpenRouterBalance {
    var label: String
    var totalCredits: Double
    var totalUsage: Double
    var keys: [OpenRouterKey] = []

    var remaining: Double { totalCredits - totalUsage }

    /// 帳號總花費減掉看得到的 key 花費。
    ///
    /// `/keys` 只涵蓋透過 provisioning API 建立的金鑰，從網頁後台建的永遠不會出現
    /// （llm-ops ADR-0002）。差額如果不顯示出來，帳號的明細會看起來比實際少花很多錢。
    var unattributedUsage: Double {
        max(0, totalUsage - keys.reduce(0) { $0 + $1.usage })
    }
}

/// OpenRouter 帳號餘額。
///
/// 語意對照 ~/dev/llm-ops/scripts/lib/analytics.mjs 的 credits()：同樣 unwrap `.data`、
/// 同樣把 body 裡的 `error` 當成失敗丟出去——OpenRouter 會用 HTTP 200 包錯誤回應，
/// 只看 status code 會把錯誤當成功。逾時也比照那邊的 30 秒。
///
/// /credits 需要 management key，一般 inference key 會 403。
enum OpenRouterSource {
    typealias Account = AppConfig.OpenRouter.Account

    /// 帳號清單與金鑰位置都來自設定檔——寫死在這裡的話，
    /// 別人 clone 下去第一件事就是要改 source code。
    static var config = AppConfig.OpenRouter()

    static var accounts: [Account] { config.accounts }

    static var envPath: URL {
        if let override = Override.url("AIMETER_OPENROUTER_ENV") { return override }
        return URL(fileURLWithPath: (config.envFile as NSString).expandingTildeInPath)
    }

    enum Failure: LocalizedError {
        case api(String)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .api(let message): return message
            case .badResponse: return "OpenRouter 回應格式不符預期"
            }
        }
    }

    private struct Envelope: Decodable {
        struct Credits: Decodable {
            var total_credits: Double
            var total_usage: Double
        }
        struct APIError: Decodable {
            var message: String?
        }
        var data: Credits?
        var error: APIError?
    }

    /// 一個帳號掛掉不該把另一個也拖下水，所以逐帳號回傳成敗。
    static func fetchAll() async -> [(label: String, result: Result<OpenRouterBalance, Error>)] {
        let env: [String: String]
        do {
            env = try DotEnv.load(envPath)
        } catch {
            return accounts.map { ($0.label, .failure(error)) }
        }

        var out: [(String, Result<OpenRouterBalance, Error>)] = []
        for account in accounts {
            guard let key = env[account.envKey], !key.isEmpty else {
                out.append((account.label, .failure(DotEnv.Failure.missingKey(account.envKey, envPath))))
                continue
            }
            do {
                out.append((account.label, .success(try await fetch(label: account.label, key: key))))
            } catch {
                out.append((account.label, .failure(error)))
            }
        }
        return out
    }

    private static func fetch(label: String, key: String) async throws -> OpenRouterBalance {
        let envelope: Envelope = try await get("/credits", key: key)

        if let error = envelope.error {
            throw Failure.api(error.message ?? "OpenRouter 回了一個錯誤")
        }
        guard let credits = envelope.data else { throw Failure.badResponse }

        return OpenRouterBalance(
            label: label,
            totalCredits: credits.total_credits,
            totalUsage: credits.total_usage,
            // 明細拿不到不該讓餘額也一起失敗——餘額才是主要資訊。
            keys: (try? await fetchKeys(key: key)) ?? []
        )
    }

    private struct KeyEnvelope: Decodable {
        struct Row: Decodable {
            var name: String?
            var limit: Double?
            var limit_remaining: Double?
            var disabled: Bool?
        }
        var data: [Row]?
    }

    private struct AnalyticsEnvelope: Decodable {
        struct Payload: Decodable {
            var data: [Row]?
        }
        struct Row: Decodable {
            var api_key_id: String?
            var total_usage: Double?
        }
        var data: Payload?
    }

    /// key 清單與花費以 **analytics** 為準，不是 `/keys`（llm-ops ADR-0002）。
    ///
    /// `/keys` 只看得到 provisioning API 建立的金鑰。實測 EnGenius 帳號用 `/keys`
    /// 只回一把 usage $0 的 "Default key"，而 analytics 回的三把
    /// （EnGenie-ASK / WiFi RegHub / DS Generator）加起來剛好等於帳號總花費。
    /// 只用 `/keys` 的話，那個帳號會看起來像沒花過錢。
    ///
    /// 但 analytics 不回「上限」，所以上限還是得跟 `/keys` 拿，兩邊用 key 名稱 join。
    private static func fetchKeys(key: String) async throws -> [OpenRouterKey] {
        async let usageRows = fetchUsageByKey(key: key)
        async let limitRows = fetchLimits(key: key)

        let usage = try await usageRows
        // 上限拿不到只是少了進度條，不該讓整份明細消失。
        let limits = (try? await limitRows) ?? [:]

        // 聯集：有花費的（analytics）＋ 有設上限但還沒花錢的（/keys）都該出現。
        let names = Set(usage.keys).union(limits.keys)

        return names
            .map { name in
                OpenRouterKey(
                    name: name,
                    usage: usage[name] ?? 0,
                    limit: limits[name]?.limit,
                    limitRemaining: limits[name]?.remaining
                )
            }
            // 有設上限的排前面，那些才是你真正在盯的
            .sorted { ($0.limit != nil ? 0 : 1, -$0.usage) < ($1.limit != nil ? 0 : 1, -$1.usage) }
    }

    private static func fetchUsageByKey(key: String) async throws -> [String: Double] {
        // time_range 的參數名不能寫成 start_date / end_date——那樣不會報錯，
        // 會靜默回傳預設區間（ADR-0002 記過這個坑）。也必須是完整 ISO datetime。
        let end = Date()
        let start = end.addingTimeInterval(-365 * 24 * 3600)
        let formatter = ISO8601DateFormatter()

        let body: [String: Any] = [
            "dimensions": ["api_key_id"],
            "metrics": ["total_usage"],
            "time_range": ["start": formatter.string(from: start), "end": formatter.string(from: end)],
            "limit": 200,
        ]

        let envelope: AnalyticsEnvelope = try await post("/analytics/query", body: body, key: key)
        var out: [String: Double] = [:]
        for row in envelope.data?.data ?? [] {
            guard let name = row.api_key_id else { continue }
            out[name, default: 0] += row.total_usage ?? 0
        }
        return out
    }

    private static func fetchLimits(key: String) async throws -> [String: (limit: Double?, remaining: Double?)] {
        let envelope: KeyEnvelope = try await get("/keys?include_disabled=false", key: key)
        var out: [String: (limit: Double?, remaining: Double?)] = [:]
        for row in envelope.data ?? [] where row.disabled != true {
            guard let name = row.name else { continue }
            out[name] = (row.limit, row.limit_remaining)
        }
        return out
    }

    private static func get<T: Decodable>(_ path: String, key: String) async throws -> T {
        try await send(request(path: path, key: key))
    }

    private static func post<T: Decodable>(_ path: String, body: [String: Any], key: String) async throws -> T {
        var req = request(path: path, key: key)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(req)
    }

    private static func request(path: String, key: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1\(path)")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        return request
    }

    private static func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
