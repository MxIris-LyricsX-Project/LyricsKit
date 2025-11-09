import Testing
import Foundation
@testable import LyricsService

let testSong = "Over"
let testArtist = "yihuik苡慧/白静晨"
let duration = 155.0
let searchReq = LyricsSearchRequest(searchTerm: .info(title: testSong, artist: testArtist), duration: duration)

struct LyricsKitTests {
    private func test(provider: LyricsProvider) async throws {
        for try await lyrics in provider.lyrics(for: searchReq) {
            print(lyrics)
        }
    }

    @Test
    func qqMusicProvider() async throws {
        try await test(provider: LyricsProviders.QQMusic())
    }

    @Test
    func LRCLIBProvider() async throws {
        try await test(provider: LyricsProviders.LRCLIB())
    }

    @Test
    func kugouProvider() async throws {
        try await test(provider: LyricsProviders.Kugou())
    }

    @Test
    func netEaseProvider() async throws {
        try await test(provider: LyricsProviders.NetEase())
    }

    @Test
    func musixmatchProvider() async throws {
        // set MUSIXMATCH_TOKEN in env to enable test
        let env = ProcessInfo.processInfo.environment
        if let token = env["MUSIXMATCH_TOKEN"], !token.isEmpty {
            await AuthenticationManagerStore.shared.setMusixmatchToken(token)

            // Alternatively you can construct provider with explicit token:
            // let provider = LyricsProviders.Musixmatch(usertoken: token)

            try await test(provider: LyricsProviders.Musixmatch())
        } else {
            print("Skipping MusixmatchProvider test: set MUSIXMATCH_TOKEN in env to enable")
        }
    }
}
