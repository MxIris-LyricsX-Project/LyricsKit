import Testing
import Foundation
@testable import LyricsService

struct NetEaseProviderTests {
    private let infoRequest = LyricsSearchRequest(
        searchTerm: .info(title: "Test Song", artist: "Test Artist"),
        duration: 200,
        limit: 3
    )

    @Test func searchHitsApiPathOnBothPasses() async throws {
        let mock = MockHTTPClient()
        let searchData = try FixtureLoader.data(named: "NetEase/search.json")
        mock.stub(host: "music.163.com",
                  response: .data(searchData, statusCode: 200,
                                  headers: ["Set-Cookie": "NMTID=abc123; Path=/; Domain=.163.com"]))
        mock.stub(hostContains: "interface3.music.163.com",
                  response: .data(try FixtureLoader.data(named: "NetEase/lyrics.json")))
        let provider = LyricsProviders.NetEase(httpClient: mock)

        _ = try await collect(provider.lyrics(for: infoRequest))

        let searchRequests = mock.recorded.filter { $0.url?.host == "music.163.com" }
        #expect(searchRequests.count == 2, "expected two-pass search to issue cookie + payload requests")
        let searchURL = try #require(searchRequests.first?.url)
        #expect(searchURL.scheme == "http")
        #expect(searchURL.path == "/api/search/pc")
        let query = searchURL.query ?? ""
        #expect(query.contains("type=1"))
        #expect(query.contains("limit=10"))
        #expect(searchRequests.first?.httpMethod == "POST")
    }

    @Test func successfullyYieldsLyrics() async throws {
        let mock = MockHTTPClient()
        mock.stub(host: "music.163.com",
                  response: .data(try FixtureLoader.data(named: "NetEase/search.json")))
        mock.stub(hostContains: "interface3.music.163.com",
                  response: .data(try FixtureLoader.data(named: "NetEase/lyrics.json")))
        let provider = LyricsProviders.NetEase(httpClient: mock)

        let lyrics = try await collect(provider.lyrics(for: infoRequest))
        let first = try #require(lyrics.first)
        #expect(first.idTags[.title] == "Test Song")
        #expect(first.idTags[.artist] == "Test Artist")
        #expect(first.idTags[.album] == "Test Album")
        #expect(first.idTags[.lrcBy] == "TestUser")
        #expect(first.metadata.serviceToken == "111111")
    }

    @Test func processingFailsWhenLyricsEmpty() async throws {
        let mock = MockHTTPClient()
        mock.stub(host: "music.163.com",
                  response: .data(try FixtureLoader.data(named: "NetEase/search.json")))
        mock.stub(hostContains: "interface3.music.163.com",
                  response: .data(try FixtureLoader.data(named: "NetEase/lyrics_empty.json")))
        let provider = LyricsProviders.NetEase(httpClient: mock)

        // Empty lyric content triggers processingFailed inside fetch.
        // The default _LyricsProvider implementation logs and skips, so stream finishes empty.
        let lyrics = try await collect(provider.lyrics(for: infoRequest))
        #expect(lyrics.isEmpty)
    }

    @Test func networkErrorPropagates() async throws {
        let mock = MockHTTPClient()
        mock.stubAny(.error(URLError(.notConnectedToInternet)))
        let provider = LyricsProviders.NetEase(httpClient: mock)

        await #expect(throws: LyricsProviderError.self) {
            _ = try await collect(provider.lyrics(for: infoRequest))
        }
    }

    @Test func decodingErrorOnSearchPropagates() async throws {
        let mock = MockHTTPClient()
        mock.stub(host: "music.163.com", response: .data(Data("not json".utf8)))
        let provider = LyricsProviders.NetEase(httpClient: mock)

        await #expect(throws: LyricsProviderError.self) {
            _ = try await collect(provider.lyrics(for: infoRequest))
        }
    }
}
