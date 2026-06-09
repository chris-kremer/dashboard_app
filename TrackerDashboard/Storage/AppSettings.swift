import Foundation
import Observation

@Observable
final class AppSettings {
    static let shared = AppSettings()

    var apiBaseURL: String {
        didSet { defaults.set(apiBaseURL, forKey: Keys.apiBaseURL) }
    }

    var spreadsheetID: String {
        didSet { defaults.set(spreadsheetID, forKey: Keys.spreadsheetID) }
    }

    var mediaAPIBaseURL: String {
        didSet { defaults.set(mediaAPIBaseURL, forKey: Keys.mediaAPIBaseURL) }
    }

    var refreshIntervalMinutes: Int {
        didSet { defaults.set(refreshIntervalMinutes, forKey: Keys.refreshIntervalMinutes) }
    }

    var apiToken: String {
        get { KeychainStore.shared.token() ?? "" }
        set { try? KeychainStore.shared.saveToken(newValue) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.apiBaseURL = defaults.string(forKey: Keys.apiBaseURL) ?? "https://tracker-dashboard-worker.chriskremer-tracker.workers.dev"
        self.spreadsheetID = defaults.string(forKey: Keys.spreadsheetID) ?? "1U2EANvtDL1X2gOTcJInN84jSwrPPeddwjKiuFrt2Mtg"
        self.mediaAPIBaseURL = defaults.string(forKey: Keys.mediaAPIBaseURL) ?? "http://10.221.81.199:8000"
        let interval = defaults.integer(forKey: Keys.refreshIntervalMinutes)
        self.refreshIntervalMinutes = interval == 0 ? 30 : interval
    }

    private enum Keys {
        static let apiBaseURL = "apiBaseURL"
        static let spreadsheetID = "spreadsheetID"
        static let mediaAPIBaseURL = "mediaAPIBaseURL"
        static let refreshIntervalMinutes = "refreshIntervalMinutes"
    }
}
