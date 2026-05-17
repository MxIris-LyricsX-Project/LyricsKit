import Foundation
@testable import LyricsService

final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    enum StubResponse {
        case data(Data, statusCode: Int = 200, headers: [String: String] = [:])
        case error(Error)
    }

    struct Stub {
        let matches: @Sendable (URLRequest) -> Bool
        let response: StubResponse
    }

    private let lock = NSLock()
    private var stubs: [Stub] = []
    private var _recorded: [URLRequest] = []

    private func synchronized<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    var recorded: [URLRequest] {
        synchronized { _recorded }
    }

    func reset() {
        synchronized {
            stubs.removeAll()
            _recorded.removeAll()
        }
    }

    func stub(matching: @escaping @Sendable (URLRequest) -> Bool, response: StubResponse) {
        synchronized { stubs.append(Stub(matches: matching, response: response)) }
    }

    func stub(path: String, response: StubResponse) {
        stub(matching: { $0.url?.path == path }, response: response)
    }

    func stub(host: String, response: StubResponse) {
        stub(matching: { $0.url?.host == host }, response: response)
    }

    func stub(hostContains substring: String, response: StubResponse) {
        stub(matching: { $0.url?.host?.contains(substring) == true }, response: response)
    }

    func stubAny(_ response: StubResponse) {
        stub(matching: { _ in true }, response: response)
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let stub: Stub? = synchronized {
            _recorded.append(request)
            return stubs.first(where: { $0.matches(request) })
        }
        guard let stub else {
            let path = request.url?.path ?? "<no url>"
            throw URLError(.unsupportedURL, userInfo: [
                NSLocalizedDescriptionKey: "MockHTTPClient: no stub matched \(path)",
            ])
        }
        switch stub.response {
        case .error(let error):
            throw error
        case .data(let data, let statusCode, let headers):
            let url = request.url ?? URL(string: "http://localhost/")!
            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            return (data, response)
        }
    }
}
