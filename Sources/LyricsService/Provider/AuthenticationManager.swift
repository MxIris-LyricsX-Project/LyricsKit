import Foundation

public protocol AuthenticationManager: Sendable {
    func isAuthenticated() async -> Bool
    func authenticate() async throws
    func getCredentials() async throws -> [String: String]
}

public enum AuthenticationError: Error {
    case notAuthenticated
    case credentialsNotFound
    case authenticationFailed(Error)
}

public actor AuthenticationManagerStore {
    public static let shared = AuthenticationManagerStore()

    private var musixmatchTokenValue: String?

    public init() {}

    /// Set (or clear) the stored Musixmatch user token.
    public func setMusixmatchToken(_ token: String?) {
        musixmatchTokenValue = token
    }

    /// Retrieve the stored Musixmatch user token, if any.
    public func musixmatchToken() -> String? {
        return musixmatchTokenValue
    }
}
