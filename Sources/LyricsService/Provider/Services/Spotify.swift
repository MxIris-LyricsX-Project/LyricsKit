import Foundation
import Regex
import LyricsCore
import FoundationToolbox

extension LyricsProviders {
    @Loggable
    public final class Spotify {
        var authenticationManager: AuthenticationManager?

        init() {}

        private func getAccessTokens() async throws -> (search: String, lyrics: String) {
            guard let authManager = authenticationManager else {
                throw AuthenticationError.notAuthenticated
            }

            if !(await authManager.isAuthenticated()) {
                try await authManager.authenticate()
            }

            let credentials = try await authManager.getCredentials()
            guard let searchToken = credentials["searchAccessToken"],
                  let lyricsToken = credentials["lyricsAccessToken"] else {
                throw AuthenticationError.credentialsNotFound
            }

            return (search: searchToken, lyrics: lyricsToken)
        }
    }
}

extension LyricsProviders.Spotify: _LyricsProvider {
    public struct LyricsToken {
        let value: SpotifyResponseSearchResult.Track.Item
    }

    public static let service: String = "Spotify"

    public func search(for request: LyricsSearchRequest) async throws -> [LyricsToken] {
        let tokens = try await getAccessTokens()

        let url: URL
        switch request.searchTerm {
        case .keyword(let string):
            guard let _url = URL(string: "https://api.spotify.com/v1/search?q=track:\(string)&type=track&limit=\(request.limit)") else { return [] }
            url = _url
        case .info(let title, let artist):
            guard let _url = URL(string: "https://api.spotify.com/v1/search?q=track:\(title) artist:\(artist)&type=track&limit=\(request.limit)") else { return [] }
            url = _url
        }

        var req = URLRequest(url: url)
        req.addValue("WebPlayer", forHTTPHeaderField: "app-platform")
        req.addValue("Bearer \(tokens.search)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let result = try JSONDecoder().decode(SpotifyResponseSearchResult.self, from: data)
            #log(.debug, "Spotify search result: \(String(describing: result))")
            return result.tracks.items.map { LyricsToken(value: $0) }
        } catch let error as DecodingError {
            throw LyricsProviderError.decodingError(underlyingError: error)
        } catch {
            throw LyricsProviderError.networkError(underlyingError: error)
        }
    }

    public func fetch(with token: LyricsToken) async throws -> Lyrics {
        let tokens = try await getAccessTokens()
        let token = token.value
        guard let url = URL(string: "https://spclient.wg.spotify.com/color-lyrics/v2/track/\(token.id)?format=json&vocalRemoval=false&market=from_token") else {
            throw LyricsProviderError.invalidURL(urlString: "Spotify fetch URL")
        }

        var request = URLRequest(url: url)
        request.addValue("WebPlayer", forHTTPHeaderField: "app-platform")
        request.addValue("Bearer \(tokens.lyrics)", forHTTPHeaderField: "Authorization")

        let singleLyricsResponse: SpotifyResponseSingleLyrics
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let jsonString = String(data: data, encoding: .utf8) {
                #log(.debug, "Spotify Received JSON: \(jsonString)")
            }
            singleLyricsResponse = try JSONDecoder().decode(SpotifyResponseSingleLyrics.self, from: data)
        } catch let error as DecodingError {
            #log(.error, "Spotify Decode error: \(error)")
            throw LyricsProviderError.decodingError(underlyingError: error)
        } catch {
            throw LyricsProviderError.networkError(underlyingError: error)
        }

        let lyrics = Lyrics(lines: singleLyricsResponse.lyrics.lines.map {
            LyricsLine(content: $0.words, position: (Double($0.startTimeMs) ?? 0) / 1000)
        }, idTags: [:])

        lyrics.idTags[.title] = token.name
        lyrics.idTags[.artist] = token.artists.map(\.name).joined(separator: ", ")
        lyrics.idTags[.album] = token.album.name
        lyrics.length = Double(token.durationMs) / 1000
        lyrics.metadata.artworkURL = token.album.images.first?.url
        lyrics.metadata.serviceToken = token.id

        return lyrics
    }
}
