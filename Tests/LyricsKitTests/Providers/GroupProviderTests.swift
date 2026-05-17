import Testing
import Foundation
@preconcurrency import LyricsCore
@testable import LyricsService

private struct StaticProvider: LyricsProvider {
    let lyricsToYield: [Lyrics]

    func lyrics(for request: LyricsSearchRequest) -> AsyncThrowingStream<Lyrics, Error> {
        AsyncThrowingStream { continuation in
            for lyric in lyricsToYield {
                continuation.yield(lyric)
            }
            continuation.finish()
        }
    }
}

private struct FailingProvider: LyricsProvider {
    let error: Error

    func lyrics(for request: LyricsSearchRequest) -> AsyncThrowingStream<Lyrics, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }
}

struct GroupProviderTests {
    private let request = LyricsSearchRequest(
        searchTerm: .info(title: "Anything", artist: "Anyone"),
        duration: 200
    )

    @Test func yieldsFromAllProviders() async throws {
        let providerA = StaticProvider(lyricsToYield: [makeLyrics(title: "A1"), makeLyrics(title: "A2")])
        let providerB = StaticProvider(lyricsToYield: [makeLyrics(title: "B1")])
        let group = LyricsProviders.Group(providers: [providerA, providerB])

        let lyrics = try await collect(group.lyrics(for: request))
        let titles = Set(lyrics.compactMap { $0.idTags[.title] })
        #expect(titles == ["A1", "A2", "B1"])
    }

    @Test func failingProviderDoesNotStopOthers() async throws {
        let failing = FailingProvider(error: LyricsProviderError.processingFailed(reason: "boom"))
        let working = StaticProvider(lyricsToYield: [makeLyrics(title: "Working")])
        let group = LyricsProviders.Group(providers: [failing, working])

        let lyrics = try await collect(group.lyrics(for: request))
        #expect(lyrics.contains(where: { $0.idTags[.title] == "Working" }))
    }

    @Test func emptyProvidersFinishesImmediately() async throws {
        let group = LyricsProviders.Group(providers: [])
        let lyrics = try await collect(group.lyrics(for: request))
        #expect(lyrics.isEmpty)
    }

    private func makeLyrics(title: String) -> Lyrics {
        let lyrics = Lyrics(lines: [LyricsLine(content: "x", position: 0)], idTags: [:])
        lyrics.idTags[.title] = title
        return lyrics
    }
}
