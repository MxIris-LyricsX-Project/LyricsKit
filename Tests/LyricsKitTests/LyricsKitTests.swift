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
        try await test(provider: LyricsProviders.Service.qq.create())
    }

    @Test
    func LRCLIBProvider() async throws {
        try await test(provider: LyricsProviders.Service.lrclib.create())
    }

    @Test
    func kugouProvider() async throws {
        try await test(provider: LyricsProviders.Service.kugou.create())
    }

    @Test
    func netEaseProvider() async throws {
        try await test(provider: LyricsProviders.Service.netease.create())
    }

    @Test
    func musixmatchProvider() async throws {
        // set MUSIXMATCH_TOKEN in env to enable test
        let env = ProcessInfo.processInfo.environment
        if let token = env["MUSIXMATCH_TOKEN"], !token.isEmpty {
            let provider = LyricsProviders.Service.musixmatch.create(.init(usertoken: token))
            try await test(provider: provider)
        } else {
            print("Skipping MusixmatchProvider test: set MUSIXMATCH_TOKEN in env to enable")
        }
    }
}
