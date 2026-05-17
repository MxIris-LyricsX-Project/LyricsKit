import Testing
import Foundation
@testable import LyricsService

struct KugouProviderTests {
    private let infoRequest = LyricsSearchRequest(
        searchTerm: .info(title: "Test Song", artist: "Test Artist"),
        duration: 200,
        limit: 3
    )

    @Test func searchBuildsCorrectURL() async throws {
        let mock = MockHTTPClient()
        mock.stub(host: "mobilecdn.kugou.com",
                  response: .data(try FixtureLoader.data(named: "Kugou/search.json")))
        mock.stub(host: "krcs.kugou.com",
                  response: .data(try FixtureLoader.data(named: "Kugou/candidates_empty.json")))
        let provider = LyricsProviders.Kugou(httpClient: mock)

        _ = try await collect(provider.lyrics(for: infoRequest))

        let searchRequest = try #require(mock.recorded.first(where: { $0.url?.host == "mobilecdn.kugou.com" }))
        #expect(searchRequest.url?.scheme == "http")
        #expect(searchRequest.url?.path == "/api/v3/search/song")
        let query = searchRequest.url?.query ?? ""
        #expect(query.contains("format=json"))
        #expect(query.contains("keyword=Test%20Song%20Test%20Artist"))
        #expect(query.contains("pagesize=20"))
    }

    @Test func processingFailsWhenNoCandidates() async throws {
        let mock = MockHTTPClient()
        mock.stub(host: "mobilecdn.kugou.com",
                  response: .data(try FixtureLoader.data(named: "Kugou/search.json")))
        mock.stub(host: "krcs.kugou.com",
                  response: .data(try FixtureLoader.data(named: "Kugou/candidates_empty.json")))
        let provider = LyricsProviders.Kugou(httpClient: mock)

        // Empty candidates: each per-token task fails internally (processingFailed),
        // and the _LyricsProvider default lyrics(for:) swallows per-task errors,
        // so stream finishes with zero yields.
        let lyrics = try await collect(provider.lyrics(for: infoRequest))
        #expect(lyrics.isEmpty)
    }

    @Test func candidatesEndpointHitsKrcsHost() async throws {
        let mock = MockHTTPClient()
        mock.stub(host: "mobilecdn.kugou.com",
                  response: .data(try FixtureLoader.data(named: "Kugou/search.json")))
        mock.stub(host: "krcs.kugou.com",
                  response: .data(try FixtureLoader.data(named: "Kugou/candidates_empty.json")))
        let provider = LyricsProviders.Kugou(httpClient: mock)

        _ = try await collect(provider.lyrics(for: infoRequest))

        let candidatesRequest = try #require(mock.recorded.first(where: { $0.url?.host == "krcs.kugou.com" }))
        let query = candidatesRequest.url?.query ?? ""
        #expect(query.contains("hash=abcdef123456"))
        #expect(query.contains("album_audio_id=222"))
        #expect(query.contains("ver=1"))
        #expect(query.contains("client=mobi"))
    }

    @Test func networkErrorOnSearchPropagates() async throws {
        let mock = MockHTTPClient()
        mock.stubAny(.error(URLError(.notConnectedToInternet)))
        let provider = LyricsProviders.Kugou(httpClient: mock)

        await #expect(throws: LyricsProviderError.self) {
            _ = try await collect(provider.lyrics(for: infoRequest))
        }
    }

    @Test func decodingErrorOnSearchPropagates() async throws {
        let mock = MockHTTPClient()
        mock.stub(host: "mobilecdn.kugou.com", response: .data(Data("garbage".utf8)))
        let provider = LyricsProviders.Kugou(httpClient: mock)

        await #expect(throws: LyricsProviderError.self) {
            _ = try await collect(provider.lyrics(for: infoRequest))
        }
    }
}
