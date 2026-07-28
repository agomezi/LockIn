//
//  NetworkManager.swift
//  Brickable
//
//  Placeholder for the future sync with the Django backend
//  (github.com/agomezi/PomodoroTimer). Nothing calls into this yet — every
//  method throws `.notImplemented`. The paths and payload shapes below match
//  the existing `api/urls.py` so filling these in is the only work left.
//

import Foundation

final class NetworkManager {
    static let shared = NetworkManager()

    enum NetworkError: LocalizedError {
        case notImplemented
        case notAuthenticated

        var errorDescription: String? {
            switch self {
            case .notImplemented:
                return "Backend sync isn't wired up yet."
            case .notAuthenticated:
                return "Sign in first."
            }
        }
    }

    /// Root of the Django REST API. Points at a local `runserver` until the
    /// backend is actually deployed somewhere.
    var baseURL = URL(string: "http://127.0.0.1:8000/api/")!

    /// Paths as defined in the backend's `api/urls.py`.
    enum Endpoint {
        static let token = "token/"
        static let tokenRefresh = "token/refresh/"
        static let register = "register/"
        static let profile = "profile/"
        static let settings = "settings/"
        static let progress = "progress/"
        static let logSession = "progress/log-session/"
        static let stats = "stats/"
    }

    /// JWT from `token/`, held once `login()` is implemented.
    private(set) var accessToken: String?

    init() {}

    // MARK: - Auth

    func login(username: String, password: String) async throws {
        throw NetworkError.notImplemented
    }

    // MARK: - Settings

    func fetchSettings() async throws -> PomodoroSettings {
        throw NetworkError.notImplemented
    }

    func pushSettings(_ settings: PomodoroSettings) async throws {
        throw NetworkError.notImplemented
    }

    // MARK: - Progress

    func logSession(durationMinutes: Int) async throws {
        throw NetworkError.notImplemented
    }

    func fetchStats() async throws -> StatsResponse {
        throw NetworkError.notImplemented
    }
}

extension NetworkManager {
    /// Shape returned by the backend's `user_stats` view.
    struct StatsResponse: Codable, Equatable {
        var totalSessions: Int
        var totalMinutes: Int
        var currentStreak: Int
        var longestStreak: Int

        enum CodingKeys: String, CodingKey {
            case totalSessions = "total_sessions"
            case totalMinutes = "total_minutes"
            case currentStreak = "current_streak"
            case longestStreak = "longest_streak"
        }
    }
}
