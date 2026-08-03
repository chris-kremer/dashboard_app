import Foundation
import Observation

@Observable
final class AppSettings {
    static let shared = AppSettings()
    private static let defaultMediaAPIBaseURL = "http://MacBook-Air-7.local:8000"
    private static let legacyMediaAPIBaseURLs = [
        "http://10.221.81.199:8000"
    ]

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

    var nudgesEnabled: Bool {
        didSet { defaults.set(nudgesEnabled, forKey: Keys.nudgesEnabled) }
    }

    var nudgeInitialDelayMinutes: Int {
        didSet { defaults.set(nudgeInitialDelayMinutes, forKey: Keys.nudgeInitialDelayMinutes) }
    }

    var nudgeRepeatIntervalMinutes: Int {
        didSet { defaults.set(nudgeRepeatIntervalMinutes, forKey: Keys.nudgeRepeatIntervalMinutes) }
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
        let savedMediaURL = defaults.string(forKey: Keys.mediaAPIBaseURL)
        if let savedMediaURL, !Self.legacyMediaAPIBaseURLs.contains(savedMediaURL) {
            self.mediaAPIBaseURL = savedMediaURL
        } else {
            self.mediaAPIBaseURL = Self.defaultMediaAPIBaseURL
        }
        let interval = defaults.integer(forKey: Keys.refreshIntervalMinutes)
        self.refreshIntervalMinutes = interval == 0 ? 30 : interval
        self.nudgesEnabled = defaults.object(forKey: Keys.nudgesEnabled) as? Bool ?? true
        self.nudgeInitialDelayMinutes = 0
        self.nudgeRepeatIntervalMinutes = 2
    }

    private enum Keys {
        static let apiBaseURL = "apiBaseURL"
        static let spreadsheetID = "spreadsheetID"
        static let mediaAPIBaseURL = "mediaAPIBaseURL"
        static let refreshIntervalMinutes = "refreshIntervalMinutes"
        static let nudgesEnabled = "nudgesEnabled"
        static let nudgeInitialDelayMinutes = "nudgeInitialDelayMinutes"
        static let nudgeRepeatIntervalMinutes = "nudgeRepeatIntervalMinutes"
    }
}
