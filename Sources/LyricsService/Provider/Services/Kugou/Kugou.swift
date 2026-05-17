import Foundation
import LyricsCore

extension LyricsProviders {
    final class Kugou {
        let httpClient: HTTPClient
        private var performer: NetworkPerformer { NetworkPerformer(httpClient: httpClient) }

        init(httpClient: HTTPClient = .shared) {
            self.httpClient = httpClient
        }
    }
}

extension LyricsProviders.Kugou: _LyricsProvider {
    struct LyricsToken {
        let value: KugouResponseSearchResult.Data.Info
    }

    static let service: String = "Kugou"

    func search(for request: LyricsSearchRequest) async throws -> [LyricsToken] {
        let endpoint = Endpoint(
            scheme: "http",
            host: "mobilecdn.kugou.com",
            path: "/api/v3/search/song",
            queryItems: [
                URLQueryItem(name: "format", value: "json"),
                URLQueryItem(name: "keyword", value: request.searchTerm.description),
                URLQueryItem(name: "page", value: "1"),
                URLQueryItem(name: "pagesize", value: "20"),
                URLQueryItem(name: "showtype", value: "1"),
            ]
        )
        let searchResult: KugouResponseSearchResult = try await performer.performJSON(endpoint)
        return searchResult.data.info.map { LyricsToken(value: $0) }
    }

    func fetch(with token: LyricsToken) async throws -> Lyrics {
        let candidatesEndpoint = Endpoint(
            host: "krcs.kugou.com",
            path: "/search",
            queryItems: [
                URLQueryItem(name: "ver", value: "1"),
                URLQueryItem(name: "man", value: "yes"),
                URLQueryItem(name: "client", value: "mobi"),
                URLQueryItem(name: "keyword", value: ""),
                URLQueryItem(name: "duration", value: ""),
                URLQueryItem(name: "hash", value: token.value.hash),
                URLQueryItem(name: "album_audio_id", value: String(token.value.albumAudioID)),
            ]
        )
        let candidatesResponse: KugouResponseSearchResultCandidates =
            try await performer.performJSON(candidatesEndpoint)

        guard let candidate = candidatesResponse.candidates.first else {
            throw LyricsProviderError.processingFailed(reason: "No candidates found for the provided token.")
        }

        let lyricsEndpoint = Endpoint(
            scheme: "http",
            host: "lyrics.kugou.com",
            path: "/download",
            queryItems: [
                URLQueryItem(name: "id", value: String(candidate.id)),
                URLQueryItem(name: "accesskey", value: candidate.accesskey),
                URLQueryItem(name: "fmt", value: "krc"),
                URLQueryItem(name: "charset", value: "utf8"),
                URLQueryItem(name: "client", value: "pc"),
                URLQueryItem(name: "ver", value: "1"),
            ]
        )
        let singleLyricsResponse: KugouResponseSingleLyrics =
            try await performer.performJSON(lyricsEndpoint)

        guard let lrcContent = decryptKugouKrc(singleLyricsResponse.content) else {
            throw LyricsProviderError.processingFailed(reason: "Failed to decrypt KRC content.")
        }

        guard let lrc = Lyrics(kugouKrcContent: lrcContent) else {
            throw LyricsProviderError.processingFailed(reason: "Failed to initialize Lyrics from KRC content.")
        }

        let coverURL = token.value.transParam?.unionCover.flatMap {
            URL(string: $0.replacingOccurrences(of: "{size}", with: "480"))
        }
        lrc.applyMetadata(
            title: candidate.song,
            artist: candidate.singer,
            lrcBy: "Kugou",
            length: Double(candidate.duration) / 1000,
            artworkURL: coverURL,
            serviceToken: "\(candidate.id),\(candidate.accesskey)"
        )
        return lrc
    }
}
