import Foundation
import LyricsCore
import Regex

extension LyricsProviders {
    final class LRCLIB {
        init() {}
    }
}

extension LyricsProviders.LRCLIB: _LyricsProvider {
    struct LyricsToken {
        let value: LRCLIBResponse
    }

    static let service: String = "LRCLIB"

    func search(for request: LyricsSearchRequest) async throws -> [LyricsToken] {
        let urlString: String
        switch request.searchTerm {
        case .keyword(let string):
            urlString = "https://lrclib.net/api/search?q=\(string)"
        case .info(let title, let artist):
            urlString = "https://lrclib.net/api/search?track_name=\(title)&artist_name=\(artist)"
        }

        guard let url = URL(string: urlString) else {
            throw LyricsProviderError.invalidURL(urlString: urlString)
        }

        do {
            let (data, _) = try await URLSession.shared.data(for: .init(url: url))
            let results = try JSONDecoder().decode([LRCLIBResponse].self, from: data)
            return results.map { LyricsToken(value: $0) }
        } catch let error as DecodingError {
            throw LyricsProviderError.decodingError(underlyingError: error)
        } catch {
            throw LyricsProviderError.networkError(underlyingError: error)
        }
    }

    func fetch(with token: LyricsToken) async throws -> Lyrics {
        if let lyrics = parseLyrics(for: token.value) {
            return lyrics
        }

        let urlString = "https://lrclib.net/api/get/\(token.value.id)"
        guard let url = URL(string: urlString) else {
            throw LyricsProviderError.invalidURL(urlString: urlString)
        }

        let fetchedToken: LRCLIBResponse
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            fetchedToken = try JSONDecoder().decode(LRCLIBResponse.self, from: data)
        } catch let error as DecodingError {
            throw LyricsProviderError.decodingError(underlyingError: error)
        } catch {
            throw LyricsProviderError.networkError(underlyingError: error)
        }

        if let lyrics = parseLyrics(for: fetchedToken) {
            return lyrics
        } else {
            throw LyricsProviderError.processingFailed(reason: "Synced lyrics not found in fetched LRCLIB response.")
        }
    }

    private func parseLyrics(for token: LRCLIBResponse) -> Lyrics? {
        guard let syncedLyrics = token.syncedLyrics, let lyrics = Lyrics(syncedLyrics) else { return nil }
        lyrics.idTags[.title] = token.trackName
        lyrics.idTags[.artist] = token.artistName
        lyrics.idTags[.album] = token.albumName
        lyrics.length = Double(token.duration)
        lyrics.metadata.serviceToken = "\(token.id)"
        return lyrics
    }
}
