import Testing
import Foundation
@testable import LyricsService

struct LRCLIBProviderTests {
    private let infoRequest = LyricsSearchRequest(
        searchTerm: .info(title: "Test Song", artist: "Test Artist"),
        duration: 200,
        limit: 5
    )
    private let keywordRequest = LyricsSearchRequest(
        searchTerm: .keyword("test query"),
        duration: 200,
        limit: 5
    )

    @Test func searchBuildsCorrectURLForInfo() async throws {
        let mock = MockHTTPClient()
        mock.stub(host: "lrclib.net", response: .data(try FixtureLoader.data(named: "LRCLIB/search.json")))
        let provider = LyricsProviders.LRCLIB(httpClient: mock)

        _ = try await collect(provider.lyrics(for: infoRequest))

        let recorded = try #require(mock.recorded.first)
        #expect(recorded.url?.scheme == "https")
        #expect(recorded.url?.host == "lrclib.net")
        #expect(recorded.url?.path == "/api/search")
        let query = recorded.url?.query ?? ""
        #expect(query.contains("track_name=Test%20Song"))
        #expect(query.contains("artist_name=Test%20Artist"))
    }

    @Test func searchBuildsCorrectURLForKeyword() async throws {
        let mock = MockHTTPClient()
        mock.stub(host: "lrclib.net", response: .data(Data("[]".utf8)))
        let provider = LyricsProviders.LRCLIB(httpClient: mock)

        _ = try await collect(provider.lyrics(for: keywordRequest))

        let query = mock.recorded.first?.url?.query ?? ""
        #expect(query.contains("q=test%20query"))
        #expect(!query.contains("track_name"))
    }

    @Test func successfullyYieldsLyricsFromSearchResults() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/search", response: .data(try FixtureLoader.data(named: "LRCLIB/search.json")))
        let provider = LyricsProviders.LRCLIB(httpClient: mock)

        let lyrics = try await collect(provider.lyrics(for: infoRequest))
        // 1st token has syncedLyrics, 2nd does not -> 1st yields, 2nd path triggers fetch
        #expect(lyrics.count >= 1)
        let first = lyrics.first!
        #expect(first.idTags[.title] == "Test Song")
        #expect(first.idTags[.artist] == "Test Artist")
        #expect(first.idTags[.album] == "Test Album")
        #expect(first.metadata.serviceToken == "12345")
    }

    @Test func fallsBackToFetchForTokenWithoutSyncedLyrics() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/api/search", response: .data(try FixtureLoader.data(named: "LRCLIB/search.json")))
        mock.stub(matching: { $0.url?.path.hasPrefix("/api/get/") == true },
                  response: .data(try FixtureLoader.data(named: "LRCLIB/get.json")))
        let provider = LyricsProviders.LRCLIB(httpClient: mock)

        _ = try await collect(provider.lyrics(for: infoRequest))

        let fetchRequest = mock.recorded.first(where: { $0.url?.path.hasPrefix("/api/get/") == true })
        let fetchPath = try #require(fetchRequest?.url?.path)
        #expect(fetchPath == "/api/get/67890")
    }

    @Test func networkErrorPropagatesAsNetworkError() async throws {
        let mock = MockHTTPClient()
        mock.stubAny(.error(URLError(.notConnectedToInternet)))
        let provider = LyricsProviders.LRCLIB(httpClient: mock)

        await #expect(throws: LyricsProviderError.self) {
            _ = try await collect(provider.lyrics(for: infoRequest))
        }
    }

    @Test func decodingErrorPropagatesAsDecodingError() async throws {
        let mock = MockHTTPClient()
        mock.stub(host: "lrclib.net", response: .data(Data("not json".utf8)))
        let provider = LyricsProviders.LRCLIB(httpClient: mock)

        await #expect(throws: LyricsProviderError.self) {
            _ = try await collect(provider.lyrics(for: infoRequest))
        }
    }
}

func collect<T>(_ stream: AsyncThrowingStream<T, Error>) async throws -> [T] {
    var items: [T] = []
    for try await item in stream {
        items.append(item)
    }
    return items
}
