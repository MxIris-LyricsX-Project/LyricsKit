import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A pluggable HTTP transport used by `LyricsProvider` implementations.
///
/// LyricsKit ships `URLSessionHTTPClient` as the production default
/// (via `HTTPClient.shared`). Tests can supply an in-memory implementation
/// to stub responses without hitting the network.
public protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPClient: HTTPClient {
    public let session: URLSession

    public init() {
        self.session = URLSession(configuration: .ephemeral)
    }

    public init(session: URLSession) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, httpResponse)
    }
}

extension URLSessionHTTPClient {
    /// Process-wide shared transport. Uses a single `URLSession(configuration: .ephemeral)`
    /// so that providers share the underlying HTTP connection pool without persisting
    /// cookies, credentials, or caches between launches.
    public static let shared = URLSessionHTTPClient()
}

extension HTTPClient where Self == URLSessionHTTPClient {
    public static var shared: URLSessionHTTPClient { URLSessionHTTPClient.shared }
}
