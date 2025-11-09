import Foundation
import LyricsCore

extension LyricsProviders {
    public final class Musixmatch {
        private let baseURL = URL(string: "https://apic-desktop.musixmatch.com/ws/1.1/")!

        private lazy var searchURL: URL = {
            return baseURL.appendingPathComponent("track.search")
        }()

        private lazy var lyricsURL: URL = {
            return baseURL.appendingPathComponent("macro.subtitles.get")
        }()

        private let usertokenOverride: String?

        private func commonQueryItems() async -> [URLQueryItem] {
            var items: [URLQueryItem] = [
                URLQueryItem(name: "format", value: "json"),
                URLQueryItem(name: "namespace", value: "lyrics_richsynched"),
                URLQueryItem(name: "subtitle_format", value: "mxm"),
                URLQueryItem(name: "app_id", value: "web-desktop-app-v1.0"),
            ]

            // Prefer the explicitly provided token; fallback to the shared store.
            let token: String?
            if let override = usertokenOverride {
                token = override
            } else {
                token = await AuthenticationManagerStore.shared.musixmatchToken()
            }

            if let token = token {
                items.append(URLQueryItem(name: "usertoken", value: token))
            }

            return items
        }

        private let headers: [String: String] = [
            "authority": "apic-desktop.musixmatch.com",
            "cookie": "x-mxm-token-guid=",
        ]

        public init(usertoken: String? = nil) {
            self.usertokenOverride = usertoken
        }
    }
}

extension LyricsProviders.Musixmatch: _LyricsProvider {
    public struct LyricsToken {
        let value: MusixmatchResponseSearchResult.Track
    }

    public static let service = "Musixmatch"

    public func search(for request: LyricsSearchRequest) async throws -> [LyricsToken] {
        // Build URL with query items
        let queryItems: [URLQueryItem]
        switch request.searchTerm {
        case .keyword(let keyword):
            queryItems = [
                URLQueryItem(name: "q", value: keyword),
                URLQueryItem(name: "f_has_lyrics", value: "1"),
            ]
        case .info(let title, let artist):
            queryItems = [
                URLQueryItem(name: "q_track", value: title),
                URLQueryItem(name: "q_artist", value: artist),
                URLQueryItem(name: "f_has_lyrics", value: "1"),
            ]
        }

        var urlComponents = URLComponents(
            url: searchURL,
            resolvingAgainstBaseURL: false
        )
        let common = await commonQueryItems()
        urlComponents?.queryItems = common + queryItems
        guard let url = urlComponents?.url else {
            throw LyricsProviderError.invalidURL(urlString: searchURL.absoluteString)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.allHTTPHeaderFields = headers

        do {
            // Request
            let (data, _) = try await URLSession.shared.data(for: urlRequest)
            let apiResponse = try JSONDecoder().decode(
                MusixmatchResponseSearchResult.self, from: data)

            // Check token validity
            if apiResponse.message.header.statusCode != 200
                && apiResponse.message.header.hint == "renew"
            {
                throw LyricsProviderError.processingFailed(reason: "Invalid Musixmatch token")
            }

            return (apiResponse.message.body?.trackList ?? []).compactMap {
                LyricsToken(value: $0.track)
            }
        } catch let error as DecodingError {
            throw LyricsProviderError.decodingError(underlyingError: error)
        } catch {
            throw LyricsProviderError.networkError(underlyingError: error)
        }
    }

    public func fetch(with token: LyricsToken) async throws -> Lyrics {
        // Check if synced lyrics are available
        if token.value.hasSubtitles == 0 {
            throw LyricsProviderError.processingFailed(reason: "Lyrics not found")
        }
        if token.value.instrumental == 1 {
            throw LyricsProviderError.processingFailed(reason: "Instrumental track")
        }

        // Build URL with query items
        let queryItems: [URLQueryItem] = [
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

        var urlComponents = URLComponents(
            url: lyricsURL,
            resolvingAgainstBaseURL: false
        )
        let common = await commonQueryItems()
        urlComponents?.queryItems = common + queryItems
        guard let url = urlComponents?.url else {
            throw LyricsProviderError.invalidURL(urlString: lyricsURL.absoluteString)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.allHTTPHeaderFields = headers

        do {
            // Request
            let (data, _) = try await URLSession.shared.data(for: urlRequest)
            let apiResponse = try JSONDecoder().decode(
                MusixmatchResponseSingleLyrics.self, from: data)

            // Check token validity
            if apiResponse.message.header.statusCode != 200
                && apiResponse.message.header.hint == "renew"
            {
                throw LyricsProviderError.processingFailed(reason: "Invalid Musixmatch token")
            }

            let body = apiResponse.message.body.macroCalls

            // Check subtitles and track availability
            guard
                body.trackSubtitlesGet?.message.header.statusCode == 200,
                body.matcherTrackGet?.message.header.statusCode == 200,
                let subtitle = body.trackSubtitlesGet?.message.body.subtitleList?.first?.subtitle
                    .subtitleBody,
                let track = body.matcherTrackGet?.message.body.track
            else {
                throw LyricsProviderError.processingFailed(reason: "Lyrics not found")
            }

            let lyrics = try parseLyrics(subtitle, with: track)
            return lyrics
        } catch let error as DecodingError {
            throw LyricsProviderError.decodingError(underlyingError: error)
        } catch let error as LyricsProviderError {
            throw error
        } catch {
            throw LyricsProviderError.networkError(underlyingError: error)
        }
    }

    private func parseLyrics(
        _ subtitleString: String,
        with track: MusixmatchResponseSearchResult.Track
    ) throws -> Lyrics {
        // Parse subtitle string as LyricsLine array
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

        let lines: [LyricsLine]
        if let subtitleData = subtitleString.data(using: .utf8) {
            do {
                let items = try JSONDecoder().decode([SubtitleItem].self, from: subtitleData)
                lines = items.map { item in
                    LyricsLine(content: item.text, position: item.time.total)
                }
            } catch let decodingError as DecodingError {
                throw LyricsProviderError.decodingError(underlyingError: decodingError)
            }
        } else {
            throw LyricsProviderError.processingFailed(reason: "Failed to encode subtitle string")
        }

        let lyrics = Lyrics(lines: lines, idTags: [:])
        lyrics.idTags[.title] = track.trackName
        lyrics.idTags[.artist] = track.artistName
        lyrics.idTags[.album] = track.albumName
        lyrics.idTags[.lrcBy] = "Musixmatch"
        lyrics.length = Double(track.trackLength)
        lyrics.metadata.artworkURL = track.albumCoverBest.isEmpty ? nil : URL(string: track.albumCoverBest)
        lyrics.metadata.serviceToken = String(track.trackId)
        return lyrics
    }
}
