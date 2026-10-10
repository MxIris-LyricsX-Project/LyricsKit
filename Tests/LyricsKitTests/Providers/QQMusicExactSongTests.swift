import Foundation
import Testing
@testable import LyricsService
import LyricsCore

struct QQMusicExactSongTests {
    private let json = #"{"id":"623777","mid":"004HzGmV3n22vM","name":"Test Song","singers":["Test Artist"],"album":"Test Album","duration":208}"#
    private func request(_ json: String) -> LyricsSearchRequest {
        LyricsSearchRequest(searchTerm: .info(title: "Test Song", artist: "Test Artist"), duration: 208, limit: 1, userInfo: ["qqmusicExactSong": json])
    }
    @Test func exactRecordBypassesBothSearchEndpoints() async throws {
        let mock = MockHTTPClient()
        let tokens = try await LyricsProviders.QQMusic(httpClient: mock).search(for: request(json))
        #expect(tokens.count == 1)
        #expect(tokens.first?.value.id == "623777")
        #expect(mock.recorded.isEmpty)
    }
    @Test func exactFetchUsesClientID() async throws {
        let mock = MockHTTPClient()
        mock.stub(path: "/qqmusic/fcgi-bin/lyric_download.fcg", response: .data(try FixtureLoader.data(named: "QQMusic/lyrics.xml")))
        let provider = LyricsProviders.QQMusic(httpClient: mock)
        let token = try #require(try await provider.search(for: request(json)).first)
        let lyrics = try await provider.fetch(with: token)
        #expect(lyrics.metadata.serviceToken == "004HzGmV3n22vM")
        let download = try #require(mock.recorded.first)
        #expect(String(data: download.httpBody ?? Data(), encoding: .utf8)?.contains("musicid=623777&") == true)
        #expect(mock.recorded.allSatisfy { $0.url?.path != "/splcloud/fcgi-bin/smartbox_new.fcg" })
    }
    @Test func invalidExactRecordFailsWithoutHiddenSearch() async throws {
        let mock = MockHTTPClient()
        await #expect(throws: (any Error).self) {
            _ = try await LyricsProviders.QQMusic(httpClient: mock).search(for: request(json.replacingOccurrences(of: "623777", with: "invalid")))
        }
        #expect(mock.recorded.isEmpty)
    }
}
