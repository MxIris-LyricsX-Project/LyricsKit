import Testing
import Foundation
@testable import LyricsService

struct QQMusicProviderTests {
    private let infoRequest = LyricsSearchRequest(
        searchTerm: .info(title: "Test Song", artist: "Test Artist"),
        duration: 200,
        limit: 5
    )

    @Test func searchHitsBothApis() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/splcloud/fcgi-bin/smartbox_new.fcg",
                  response: .data(try FixtureLoader.data(named: "QQMusic/search1.json")))
        mock.stub(path: "/cgi-bin/musicu.fcg",
                  response: .data(try FixtureLoader.data(named: "QQMusic/search2.json")))
        mock.stub(path: "/qqmusic/fcgi-bin/lyric_download.fcg",
                  response: .data(try FixtureLoader.data(named: "QQMusic/lyrics.xml")))

        let provider = LyricsProviders.QQMusic(httpClient: mock)
        _ = try await collect(provider.lyrics(for: infoRequest))

        let api1 = mock.recorded.first(where: { $0.url?.path == "/splcloud/fcgi-bin/smartbox_new.fcg" })
        let api2 = mock.recorded.first(where: { $0.url?.path == "/cgi-bin/musicu.fcg" })
        #expect(api1 != nil)
        #expect(api2 != nil)
        let api1Query = api1?.url?.query ?? ""
        #expect(api1Query.contains("key=Test%20Song%20Test%20Artist"))
        #expect(api2?.httpMethod == "POST")
    }

    @Test func successfullyYieldsPlaintextLyrics() async throws {
        let mock = MockHTTPClient()
        let search1Data = try FixtureLoader.data(named: "QQMusic/search1.json")
        let search2Data = try FixtureLoader.data(named: "QQMusic/search2.json")
        let lyricsXMLData = try FixtureLoader.data(named: "QQMusic/lyrics.xml")
        let songDetailData = try FixtureLoader.data(named: "QQMusic/song_detail.json")

        mock.stub(path: "/splcloud/fcgi-bin/smartbox_new.fcg",
                  response: .data(search1Data))
        // First matching stub wins: route /cgi-bin/musicu.fcg POSTs by body content.
        mock.stub(matching: { request in
            guard request.url?.path == "/cgi-bin/musicu.fcg" else { return false }
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            return body.contains("get_song_detail_yqq")
        }, response: .data(songDetailData))
        mock.stub(path: "/cgi-bin/musicu.fcg", response: .data(search2Data))
        mock.stub(path: "/qqmusic/fcgi-bin/lyric_download.fcg", response: .data(lyricsXMLData))

        let provider = LyricsProviders.QQMusic(httpClient: mock)
        let lyrics = try await collect(provider.lyrics(for: infoRequest))
        #expect(!lyrics.isEmpty)
        let first = try #require(lyrics.first)
        #expect(first.idTags[.title] != nil)
        #expect(first.idTags[.artist] != nil)
        #expect(first.metadata.serviceToken != nil)
        #expect(first.metadata.artworkURL?.absoluteString.contains("albumMid123") == true)
    }

    @Test func networkErrorsOnBothApisThrowProcessingFailed() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/splcloud/fcgi-bin/smartbox_new.fcg",
                  response: .error(URLError(.notConnectedToInternet)))
        mock.stub(path: "/cgi-bin/musicu.fcg",
                  response: .error(URLError(.notConnectedToInternet)))

        let provider = LyricsProviders.QQMusic(httpClient: mock)
        // Both search APIs swallow their own errors and return []; the search wrapper
        // then raises processingFailed instead of returning a silently-empty result.
        await #expect(throws: LyricsProviderError.self) {
            _ = try await collect(provider.lyrics(for: infoRequest))
        }
    }

    @Test func processingFailsWhenLyricsXMLEmpty() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/splcloud/fcgi-bin/smartbox_new.fcg",
                  response: .data(try FixtureLoader.data(named: "QQMusic/search1.json")))
        mock.stub(path: "/cgi-bin/musicu.fcg",
                  response: .data(try FixtureLoader.data(named: "QQMusic/search2.json")))
        mock.stub(path: "/qqmusic/fcgi-bin/lyric_download.fcg",
                  response: .data(Data("<root></root>".utf8)))

        let provider = LyricsProviders.QQMusic(httpClient: mock)
        // fetch fails for every token, default stream finishes with zero yields.
        let lyrics = try await collect(provider.lyrics(for: infoRequest))
        #expect(lyrics.isEmpty)
    }
}
