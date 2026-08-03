import Foundation

actor TrackerAPIClient {
    static let shared = TrackerAPIClient()

    private let session: URLSession
    private let settings: AppSettings

    init(session: URLSession = .shared, settings: AppSettings = .shared) {
        self.session = session
        self.settings = settings
    }

    func fetchSnapshot(date: String = Date.trackerDateFormatter.string(from: Date())) async throws -> TrackerSnapshot {
        var components = URLComponents(url: try baseURL().appendingPathComponent("snapshot"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "date", value: date)]
        guard let url = components?.url else { throw APIError.invalidURL }
        return try await send(URLRequest(url: url), responseType: TrackerSnapshot.self)
    }

    func createTask(_ request: CreateTaskRequest) async throws -> ScheduleItem {
        try await sendJSON(request, method: "POST", path: "tasks", responseType: ScheduleItem.self)
    }

    func updateTask(rowNumber: Int, patch: TaskPatchRequest) async throws -> ScheduleItem {
        try await sendJSON(patch, method: "PATCH", path: "tasks/\(rowNumber)", responseType: ScheduleItem.self)
    }

    func completeTask(rowNumber: Int, source: String, stop: String? = nil) async throws -> ScheduleItem {
        try await sendJSON(CompleteTaskRequest(source: source, stop: stop), method: "POST", path: "tasks/\(rowNumber)/complete", responseType: ScheduleItem.self)
    }

    func logCaffeine(_ request: CaffeineRequest) async throws -> CaffeineEntry {
        try await sendJSON(request, method: "POST", path: "caffeine", responseType: CaffeineEntry.self)
    }

    func logFood(_ request: FoodRequest) async throws -> FoodEntry {
        try await sendJSON(request, method: "POST", path: "food", responseType: FoodEntry.self)
    }

    func upsertSleep(_ request: SleepRequest) async throws -> SleepEntry {
        try await sendJSON(request, method: "POST", path: "sleep", responseType: SleepEntry.self)
    }

    func updateNudgeSettings(_ request: NudgeSettingsRequest) async throws {
        _ = try await sendJSON(request, method: "PUT", path: "nudge/settings", responseType: NudgeAPIResponse.self)
    }

    func registerNudgeDevice(_ request: NudgeDeviceRequest) async throws {
        _ = try await sendJSON(request, method: "POST", path: "nudge/devices", responseType: NudgeAPIResponse.self)
    }

    func sendNudgeCommand(_ request: NudgeCommandRequest) async throws {
        _ = try await sendJSON(request, method: "POST", path: "nudge/command", responseType: NudgeAPIResponse.self)
    }

    func sendTestNudge() async throws {
        _ = try await sendJSON(NudgeCommandRequest(command: "test", minutes: nil), method: "POST", path: "nudge/test", responseType: NudgeAPIResponse.self)
    }

    func fetchMediaSessions() async throws -> MediaSessionsResponse {
        try await send(URLRequest(url: try baseURL().appendingPathComponent("media/sessions")), responseType: MediaSessionsResponse.self)
    }

    func fetchNudgeHistory(limit: Int = 100) async throws -> NudgeHistoryResponse {
        var components = URLComponents(url: try baseURL().appendingPathComponent("nudge/history"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        guard let url = components?.url else { throw APIError.invalidURL }
        return try await send(URLRequest(url: url), responseType: NudgeHistoryResponse.self)
    }

    private func sendJSON<Request: Encodable, Response: Decodable>(
        _ body: Request,
        method: String,
        path: String,
        responseType: Response.Type
    ) async throws -> Response {
        var request = URLRequest(url: try baseURL().appendingPathComponent(path))
        request.httpMethod = method
        request.httpBody = try TrackerJSON.encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await send(request, responseType: responseType)
    }

    private func send<Response: Decodable>(_ request: URLRequest, responseType: Response.Type) async throws -> Response {
        var request = request
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let token = settings.apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let message = String(data: data, encoding: .utf8)
            throw APIError.httpStatus(httpResponse.statusCode, message)
        }
        return try TrackerJSON.decoder.decode(Response.self, from: data)
    }

    private func baseURL() throws -> URL {
        guard let url = URL(string: settings.apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased()) else {
            throw APIError.invalidURL
        }
        return url
    }
}

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The API base URL is invalid."
        case .invalidResponse:
            "The server returned an invalid response."
        case .httpStatus(let status, let message):
            "API request failed with HTTP \(status)\(message.map { ": \($0)" } ?? "")."
        }
    }
}
