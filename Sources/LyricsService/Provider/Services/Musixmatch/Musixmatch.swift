import Foundation
import LyricsCore

extension LyricsProviders {
    public struct MusixmatchOptions: LyricsProviderOptions {
        public var usertoken: String?

        public init() {}

        public init(usertoken: String?) {
            self.usertoken = usertoken
        }
    }

    final class Musixmatch {
        let httpClient: HTTPClient
        let options: MusixmatchOptions

        private var performer: NetworkPerformer { NetworkPerformer(httpClient: httpClient) }

        init(options: MusixmatchOptions = .init(), httpClient: HTTPClient = .shared) {
            self.options = options
            self.httpClient = httpClient
        }

        private static let host = "apic-desktop.musixmatch.com"
        private static let searchPath = "/ws/1.1/track.search"
        private static let lyricsPath = "/ws/1.1/macro.subtitles.get"

        private static let headers: [String: String] = [
            "authority": "apic-desktop.musixmatch.com",
            "cookie": "x-mxm-token-guid=",
        ]

        private func commonQueryItems() -> [URLQueryItem] {
            var items: [URLQueryItem] = [
                URLQueryItem(name: "format", value: "json"),
                URLQueryItem(name: "namespace", value: "lyrics_richsynched"),
                URLQueryItem(name: "subtitle_format", value: "mxm"),
                URLQueryItem(name: "app_id", value: "web-desktop-app-v1.0"),
            ]
            if let token = options.usertoken {
                items.append(URLQueryItem(name: "usertoken", value: token))
            }
            return items
        }
    }
}

extension LyricsProviders.Musixmatch: _LyricsProvider {
    struct LyricsToken {
        let value: MusixmatchResponseSearchResult.Track
    }

    static let service: String = "Musixmatch"

    func search(for request: LyricsSearchRequest) async throws -> [LyricsToken] {
        let termItems: [URLQueryItem]
        switch request.searchTerm {
        case .keyword(let keyword):
            termItems = [
                URLQueryItem(name: "q", value: keyword),
                URLQueryItem(name: "f_has_lyrics", value: "1"),
            ]
        case .info(let title, let artist):
            termItems = [
                URLQueryItem(name: "q_track", value: title),
                URLQueryItem(name: "q_artist", value: artist),
                URLQueryItem(name: "f_has_lyrics", value: "1"),
            ]
        }

        let endpoint = Endpoint(
            host: Self.host,
            path: Self.searchPath,
            queryItems: commonQueryItems() + termItems,
            headers: Self.headers
        )

        let apiResponse: MusixmatchResponseSearchResult = try await performer.performJSON(endpoint)
        try Self.checkTokenValidity(
            statusCode: apiResponse.message.header.statusCode,
            hint: apiResponse.message.header.hint
        )
        return (apiResponse.message.body?.trackList ?? []).map { LyricsToken(value: $0.track) }
    }

    func fetch(with token: LyricsToken) async throws -> Lyrics {
        if token.value.hasSubtitles == 0 {
            throw LyricsProviderError.processingFailed(reason: "Lyrics not found")
        }
        if token.value.instrumental == 1 {
            throw LyricsProviderError.processingFailed(reason: "Instrumental track")
        }

        let lyricItems: [URLQueryItem] = [
            URLQueryItem(name: "q_album", value: token.value.albumName),
            URLQueryItem(name: "q_artist", value: token.value.artistName),
            URLQueryItem(name: "q_artists", value: token.value.artistName),
            URLQueryItem(name: "q_track", value: token.value.trackName),
            URLQueryItem(name: "track_spotify_id", value: token.value.trackSpotifyId),
            URLQueryItem(name: "q_duration", value: String(token.value.trackLength)),
            URLQueryItem(
                name: "f_subtitle_length",
                value: String(Int(floor(Double(token.value.trackLength))))
            ),
        ]

        let endpoint = Endpoint(
            host: Self.host,
            path: Self.lyricsPath,
            queryItems: commonQueryItems() + lyricItems,
            headers: Self.headers
        )

        let apiResponse: MusixmatchResponseSingleLyrics = try await performer.performJSON(endpoint)
        try Self.checkTokenValidity(
            statusCode: apiResponse.message.header.statusCode,
            hint: apiResponse.message.header.hint
        )

        let body = apiResponse.message.body.macroCalls
        guard
            body.trackSubtitlesGet?.message.header.statusCode == 200,
            body.matcherTrackGet?.message.header.statusCode == 200,
            let subtitle = body.trackSubtitlesGet?.message.body.subtitleList?.first?.subtitle.subtitleBody,
            let track = body.matcherTrackGet?.message.body.track
        else {
            throw LyricsProviderError.processingFailed(reason: "Lyrics not found")
        }

        return try parseLyrics(subtitle, with: track)
    }

    private static func checkTokenValidity(statusCode: Int, hint: String?) throws {
        if statusCode != 200, hint == "renew" {
            throw LyricsProviderError.processingFailed(reason: "Invalid Musixmatch token")
        }
    }

    private func parseLyrics(
        _ subtitleString: String,
        with track: MusixmatchResponseSearchResult.Track
    ) throws -> Lyrics {
        struct SubtitleItem: Decodable {
            let text: String
            let time: TimeInfo
            struct TimeInfo: Decodable {
                let total: Double
                let minutes: Int
                let seconds: Int
                let hundredths: Int
            }
        }

        guard let subtitleData = subtitleString.data(using: .utf8) else {
            throw LyricsProviderError.processingFailed(reason: "Failed to encode subtitle string")
        }
        let items: [SubtitleItem]
        do {
            items = try JSONDecoder().decode([SubtitleItem].self, from: subtitleData)
        } catch let error as DecodingError {
            throw LyricsProviderError.decodingError(underlyingError: error)
        }

        let lines = items.map { LyricsLine(content: $0.text, position: $0.time.total) }
        let lyrics = Lyrics(lines: lines, idTags: [:])
        let coverURL = track.albumCoverBest.isEmpty ? nil : URL(string: track.albumCoverBest)
        lyrics.applyMetadata(
            title: track.trackName,
            artist: track.artistName,
            album: track.albumName,
            lrcBy: "Musixmatch",
            length: Double(track.trackLength),
            artworkURL: coverURL,
            serviceToken: String(track.trackId)
        )
        return lyrics
    }
}
