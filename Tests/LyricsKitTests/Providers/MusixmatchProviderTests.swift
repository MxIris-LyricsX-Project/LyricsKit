import Testing
import Foundation
@testable import LyricsService

struct MusixmatchProviderTests {
    private let infoRequest = LyricsSearchRequest(
        searchTerm: .info(title: "Test Song", artist: "Test Artist"),
        duration: 200,
        limit: 3
    )

    @Test func searchBuildsCorrectURL() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/ws/1.1/track.search",
                  response: .data(try FixtureLoader.data(named: "Musixmatch/search.json")))
        mock.stub(path: "/ws/1.1/macro.subtitles.get",
                  response: .data(try FixtureLoader.data(named: "Musixmatch/lyrics.json")))
        let provider = LyricsProviders.Musixmatch(
            options: .init(usertoken: "test-token"),
            httpClient: mock
        )

        _ = try await collect(provider.lyrics(for: infoRequest))

        let searchRequest = try #require(mock.recorded.first(where: { $0.url?.path == "/ws/1.1/track.search" }))
        #expect(searchRequest.url?.host == "apic-desktop.musixmatch.com")
        let query = searchRequest.url?.query ?? ""
        #expect(query.contains("q_track=Test%20Song"))
        #expect(query.contains("q_artist=Test%20Artist"))
        #expect(query.contains("f_has_lyrics=1"))
        #expect(query.contains("usertoken=test-token"))
        #expect(query.contains("namespace=lyrics_richsynched"))
        #expect(query.contains("app_id=web-desktop-app-v1.0"))
    }

    @Test func searchUsesKeywordWhenNoArtist() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/ws/1.1/track.search",
                  response: .data(Data(#"{"message":{"header":{"status_code":200,"hint":null},"body":{"track_list":[]}}}"#.utf8)))
        let provider = LyricsProviders.Musixmatch(httpClient: mock)

        let request = LyricsSearchRequest(searchTerm: .keyword("hello"), duration: 200)
        _ = try await collect(provider.lyrics(for: request))

        let recorded = try #require(mock.recorded.first)
        let query = recorded.url?.query ?? ""
        #expect(query.contains("q=hello"))
        #expect(!query.contains("q_track"))
    }

    @Test func successfullyYieldsLyrics() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/ws/1.1/track.search",
                  response: .data(try FixtureLoader.data(named: "Musixmatch/search.json")))
        mock.stub(path: "/ws/1.1/macro.subtitles.get",
                  response: .data(try FixtureLoader.data(named: "Musixmatch/lyrics.json")))
        let provider = LyricsProviders.Musixmatch(httpClient: mock)

        let lyrics = try await collect(provider.lyrics(for: infoRequest))
        #expect(lyrics.count == 1)
        let first = try #require(lyrics.first)
        #expect(first.idTags[.title] == "Test Song")
        #expect(first.idTags[.artist] == "Test Artist")
        #expect(first.idTags[.album] == "Test Album")
        #expect(first.idTags[.lrcBy] == "Musixmatch")
        #expect(first.metadata.serviceToken == "123456")
        #expect(first.length == 200)
        #expect(first.lines.count == 2)
        #expect(first.lines[0].content == "first line")
        #expect(first.lines[1].content == "second line")
        #expect(first.lines[1].position == 3.5)
    }

    @Test func invalidTokenRaisesProcessingFailed() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/ws/1.1/track.search",
                  response: .data(Data(#"{"message":{"header":{"status_code":401,"hint":"renew"},"body":null}}"#.utf8)))
        let provider = LyricsProviders.Musixmatch(httpClient: mock)

        await #expect(throws: LyricsProviderError.self) {
            _ = try await collect(provider.lyrics(for: infoRequest))
        }
    }

    @Test func networkErrorPropagates() async throws {
        let mock = MockHTTPClient()
        mock.stubAny(.error(URLError(.timedOut)))
        let provider = LyricsProviders.Musixmatch(httpClient: mock)

        await #expect(throws: LyricsProviderError.self) {
            _ = try await collect(provider.lyrics(for: infoRequest))
        }
    }
}
