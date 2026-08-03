import Foundation

actor MediaAPIClient {
    static let shared = MediaAPIClient()

    private let session: URLSession
    private let settings: AppSettings

    init(session: URLSession = MediaAPIClient.makeSession(), settings: AppSettings = .shared) {
        self.session = session
        self.settings = settings
    }

    func fetchStatus() async throws -> MediaStatus {
        try await send(path: "api/status", responseType: MediaStatus.self)
    }

    func fetchEvents(date: String = Date.trackerDateFormatter.string(from: Date())) async throws -> MediaEventsResponse {
        var components = URLComponents(
            url: try mediaBaseURL().appendingPathComponent("api/events"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "date", value: date)]
        guard let url = components?.url else {
            throw APIError.invalidURL
        }
        return try await send(url: url, responseType: MediaEventsResponse.self)
    }

    private func send<Response: Decodable>(path: String, responseType: Response.Type) async throws -> Response {
        try await send(url: try mediaBaseURL().appendingPathComponent(path), responseType: responseType)
    }

    private func send<Response: Decodable>(url: URL, responseType: Response.Type) async throws -> Response {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
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

    private func mediaBaseURL() throws -> URL {
        guard let url = URL(string: settings.mediaAPIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased()) else {
            throw APIError.invalidURL
        }
        return url
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }
}
