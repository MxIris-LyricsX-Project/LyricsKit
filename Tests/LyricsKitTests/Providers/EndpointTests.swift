import Testing
import Foundation
@testable import LyricsService

struct EndpointTests {
    @Test func buildRequestSetsURLComponents() throws {
        let endpoint = Endpoint(
            scheme: "https",
            host: "example.com",
            path: "/api/search",
            queryItems: [
                URLQueryItem(name: "q", value: "hello world"),
                URLQueryItem(name: "limit", value: "10"),
            ]
        )
        let request = try endpoint.buildRequest()
        #expect(request.url?.scheme == "https")
        #expect(request.url?.host == "example.com")
        #expect(request.url?.path == "/api/search")
        #expect(request.url?.query?.contains("q=hello%20world") == true)
        #expect(request.url?.query?.contains("limit=10") == true)
        #expect(request.httpMethod == "GET")
    }

    @Test func buildRequestSetsMethodHeadersAndBody() throws {
        let body = Data("payload".utf8)
        let endpoint = Endpoint(
            host: "example.com",
            path: "/post",
            method: .post,
            headers: ["X-Test": "value", "Content-Type": "application/json"],
            body: body
        )
        let request = try endpoint.buildRequest()
        #expect(request.httpMethod == "POST")
        #expect(request.httpBody == body)
        #expect(request.value(forHTTPHeaderField: "X-Test") == "value")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func buildRequestThrowsInvalidURLOnInconsistentComponents() {
        // URLComponents.url is nil when an authority component is present but the path
        // does not start with "/" (RFC 3986 §3.3).
        let endpoint = Endpoint(host: "example.com", path: "no-leading-slash")
        #expect(throws: LyricsProviderError.self) {
            try endpoint.buildRequest()
        }
    }

    @Test func buildRequestPassesEmptyHostThroughURLComponents() throws {
        // URLComponents tolerates an empty host (produces `scheme:/path`).
        // We do not block this here — `Endpoint.absolute` is the hardened entrypoint
        // for caller-supplied URL strings.
        let endpoint = Endpoint(host: "", path: "/x")
        let request = try endpoint.buildRequest()
        #expect(request.url != nil)
    }

    @Test func absoluteThrowsForInvalidURL() {
        #expect(throws: LyricsProviderError.self) {
            _ = try Endpoint.absolute("")
        }
    }

    @Test func absoluteRejectsDisallowedSchemes() {
        for urlString in [
            "file:///etc/passwd",
            "data:text/plain;base64,SGVsbG8=",
            "javascript:alert(1)",
            "ftp://example.com/resource",
        ] {
            #expect(throws: LyricsProviderError.self) {
                _ = try Endpoint.absolute(urlString)
            }
        }
    }

    @Test func absoluteRejectsMissingHost() {
        #expect(throws: LyricsProviderError.self) {
            _ = try Endpoint.absolute("https:///path-only")
        }
    }

    @Test func absoluteBuildsRequestForValidURL() throws {
        let request = try Endpoint.absolute(
            "https://example.com/api",
            method: .post,
            headers: ["X-Auth": "token"],
            body: Data("body".utf8)
        )
        #expect(request.url?.absoluteString == "https://example.com/api")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "X-Auth") == "token")
        #expect(request.httpBody == Data("body".utf8))
    }
}
