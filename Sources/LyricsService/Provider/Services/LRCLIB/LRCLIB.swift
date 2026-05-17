import Foundation
import LyricsCore

extension LyricsProviders {
    final class LRCLIB {
        let httpClient: HTTPClient
        private var performer: NetworkPerformer { NetworkPerformer(httpClient: httpClient) }

        init(httpClient: HTTPClient = .shared) {
            self.httpClient = httpClient
        }
    }
}

extension LyricsProviders.LRCLIB: _LyricsProvider {
    struct LyricsToken {
        let value: LRCLIBResponse
    }

    static let service: String = "LRCLIB"

    func search(for request: LyricsSearchRequest) async throws -> [LyricsToken] {
        let queryItems: [URLQueryItem]
        switch request.searchTerm {
        case .keyword(let keyword):
            queryItems = [URLQueryItem(name: "q", value: keyword)]
        case .info(let title, let artist):
            queryItems = [
                URLQueryItem(name: "track_name", value: title),
                URLQueryItem(name: "artist_name", value: artist),
            ]
        }
        let endpoint = Endpoint(
            host: "lrclib.net",
            path: "/api/search",
            queryItems: queryItems
        )
        let results: [LRCLIBResponse] = try await performer.performJSON(endpoint)
        return results.map { LyricsToken(value: $0) }
    }

    func fetch(with token: LyricsToken) async throws -> Lyrics {
        if let lyrics = parseLyrics(for: token.value) {
            return lyrics
        }

        let endpoint = Endpoint(
            host: "lrclib.net",
            path: "/api/get/\(token.value.id)"
        )
        let fetchedToken: LRCLIBResponse = try await performer.performJSON(endpoint)

        guard let lyrics = parseLyrics(for: fetchedToken) else {
            throw LyricsProviderError.processingFailed(reason: "Synced lyrics not found in fetched LRCLIB response.")
        }
        return lyrics
    }

    private func parseLyrics(for token: LRCLIBResponse) -> Lyrics? {
        guard let syncedLyrics = token.syncedLyrics,
              let lyrics = Lyrics(syncedLyrics) else { return nil }
        lyrics.applyMetadata(
            title: token.trackName,
            artist: token.artistName,
            album: token.albumName,
            length: Double(token.duration),
            serviceToken: "\(token.id)"
        )
        return lyrics
    }
}
