import Foundation
import os
import LyricsCore
import LyricsService

// MARK: - Apple Music Lyrics Provider

/// Fetches word-timed (syllable) lyrics from Apple Music via the internal
/// amp-api.
///
/// The syllable-lyrics endpoint is NOT part of the public MusicKit catalog
/// API — it only responds to a request that carries both a `media-user-token`
/// (proving the active subscription) and the web player's `AMPWebPlay`
/// developer token. `MusicDataRequest` returns HTML/401 on this path.
/// Catalog search and `/v1/me/storefront` accept the same auth, so this
/// provider depends only on `AppleMusicSession`; the MusicKit-backed
/// `AppleMusicCatalog` is reserved for the no-token Route B (name recovery).
@available(macOS 12.0, *)
extension LyricsProviders {
    public final class AppleMusic {
        let httpClient: HTTPClient

        public init(httpClient: HTTPClient = URLSessionHTTPClient.shared) {
            self.httpClient = httpClient
        }
    }
}

// MARK: - _LyricsProvider

@available(macOS 12.0, *)
extension LyricsProviders.AppleMusic: _LyricsProvider {

    public struct LyricsToken: Sendable {
        public let song: AppleMusicCatalogSong
    }

    public static let service: String = "Apple Music"

    public func search(for request: LyricsSearchRequest) async throws -> [LyricsToken] {
        let storefront = try await resolveStorefront()

        let searchTerm: String
        let filterArtist: String?
        let fallbackKeyword: String?
        switch request.searchTerm {
        case .keyword(let keyword):
            searchTerm = keyword
            filterArtist = nil
            fallbackKeyword = nil
        case .info(let title, let artist):
            searchTerm = title
            filterArtist = artist.lowercased()
            fallbackKeyword = "\(title) \(artist)"
        }

        var songs = try await catalogSearch(term: searchTerm, storefront: storefront)
        var filtered = applyArtistFilter(songs: songs, artist: filterArtist)

        // Title-only + artist filter sometimes yields nothing (artist is romanized
        // away or stored as a slightly different string). Apple Music's own
        // search engine matches title + artist together and rarely misses, so
        // fall back to a combined keyword search.
        if filtered.isEmpty, let fallback = fallbackKeyword {
            songs = try await catalogSearch(term: fallback, storefront: storefront)
            filtered = applyArtistFilter(songs: songs, artist: filterArtist)
        }

        return filtered.map { LyricsToken(song: $0) }
    }

    public func fetch(with token: LyricsToken) async throws -> Lyrics {
        let storefront = try await resolveStorefront()
        let songID = token.song.id

        // Apple Music requires `&l=<lang>` to include translations in the TTML
        // response. Without it, `<translations/>` is always empty.
        let language = await resolveLanguage()
        let path = "/v1/catalog/\(storefront)/songs/\(songID)/syllable-lyrics"
            + "?l=\(language)&extend=ttmlLocalizations"

        let data: Data
        do {
            data = try await AppleMusicSession.shared.musicAPI(path)
        } catch {
            throw LyricsProviderError.processingFailed(
                reason: "Apple Music amp-api request failed: \(error.localizedDescription)")
        }

        let response: TTMLLyricsResponse
        do {
            let wrapper = try JSONDecoder().decode(MusicKitWrapper<TTMLLyricsResponse>.self, from: data)
            response = wrapper.unwrapped
        } catch {
            throw LyricsProviderError.processingFailed(
                reason: "Failed to decode TTML response: \(error.localizedDescription)")
        }

        guard let ttml = response.data.first?.attributes.ttmlLocalizations, !ttml.isEmpty else {
            throw LyricsProviderError.processingFailed(
                reason: "No syllable lyrics available for this track.")
        }

        guard let lyrics = Lyrics(ttmlContent: ttml) else {
            throw LyricsProviderError.processingFailed(
                reason: "Failed to parse TTML lyrics for track \(songID)")
        }

        // Reject if no line has any timing data — the TTML envelope existed
        // but its content was empty/garbled.
        let hasLinesWithTime = lyrics.lines.contains { line in
            line.position != 0 || line.attachments.timetag != nil
        }
        guard hasLinesWithTime else {
            throw LyricsProviderError.processingFailed(
                reason: "No syllable lyrics available for this track.")
        }

        lyrics.applyMetadata(
            title: token.song.name,
            artist: token.song.artistName,
            album: token.song.albumName,
            length: token.song.durationInMillis.map { Double($0) / 1000.0 },
            serviceToken: token.song.id)

        return lyrics
    }

    // MARK: - Helpers

    /// Resolve the storefront via override or `/v1/me/storefront`.
    private func resolveStorefront() async throws -> String {
        if let override = await AppleMusicSession.shared.storefrontOverride,
           !override.isEmpty {
            return override
        }
        let data = try await AppleMusicSession.shared.musicAPI("/v1/me/storefront")
        let wrapper = try JSONDecoder().decode(MusicKitWrapper<StorefrontResponse>.self, from: data)
        guard let id = wrapper.unwrapped.data.first?.id else {
            throw AppleMusicError.unexpectedResponse
        }
        return id
    }

    /// Override or `Locale.preferredLanguages` first entry, capped to 5 chars.
    private func resolveLanguage() async -> String {
        if let override = await AppleMusicSession.shared.languageOverride,
           !override.isEmpty {
            return override
        }
        return Locale.preferredLanguages.first.flatMap { String($0.prefix(5)) }
            ?? "zh-Hans"
    }

    /// Catalog search via amp-api (Route A transport). Manually URL-encodes
    /// the term so characters like `&`, `+`, `#` cannot break the path the
    /// web player passes to `music.api.music()`.
    private func catalogSearch(term: String, storefront: String)
        async throws -> [AppleMusicCatalogSong]
    {
        let encoded = term.addingPercentEncoding(
            withAllowedCharacters: {
                var characters = CharacterSet.urlQueryAllowed
                characters.remove(charactersIn: "&$+,\n#")
                return characters
            }()) ?? term
        let path = "/v1/catalog/\(storefront)/search?term=\(encoded)&types=songs&limit=10"
        let data = try await AppleMusicSession.shared.musicAPI(path)
        let wrapper = try JSONDecoder().decode(MusicKitWrapper<SearchResponse>.self, from: data)
        return (wrapper.unwrapped.results.songs?.data ?? []).map(\.flattened)
    }

    /// Keep only songs whose `artistName` overlaps with the requested artist.
    /// `contains` in both directions tolerates "artist A, artist B" and
    /// "artist A (feat. X)" variations.
    private func applyArtistFilter(songs: [AppleMusicCatalogSong], artist: String?)
        -> [AppleMusicCatalogSong]
    {
        guard let artist else { return songs }
        return songs.filter {
            let candidate = $0.artistName.lowercased()
            return candidate.contains(artist) || artist.contains(candidate)
        }
    }
}

// MARK: - amp-api wire models

/// `music.api.music(path)` may return either `{ "data": <payload> }` or the
/// raw payload itself, depending on which response shape the web player
/// happens to surface. Decode tolerantly by trying both.
private struct MusicKitWrapper<Payload: Decodable>: Decodable {
    let unwrapped: Payload

    private enum CodingKeys: String, CodingKey {
        case data
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let payload = try? container.decode(Payload.self, forKey: .data) {
            self.unwrapped = payload
        } else {
            self.unwrapped = try Payload(from: decoder)
        }
    }
}

private struct StorefrontResponse: Decodable {
    let data: [Storefront]

    struct Storefront: Decodable {
        let id: String
    }
}

private struct SearchResponse: Decodable {
    let results: Results

    struct Results: Decodable {
        let songs: SongList?

        struct SongList: Decodable {
            let data: [CatalogSongResource]
        }
    }
}

private struct CatalogSongResource: Decodable {
    let id: String
    let attributes: Attributes

    struct Attributes: Decodable {
        let name: String
        let artistName: String
        let albumName: String?
        let isrc: String?
        let durationInMillis: Int?
    }

    var flattened: AppleMusicCatalogSong {
        AppleMusicCatalogSong(
            id: id,
            name: attributes.name,
            artistName: attributes.artistName,
            albumName: attributes.albumName,
            isrc: attributes.isrc,
            durationInMillis: attributes.durationInMillis)
    }
}

private struct TTMLLyricsResponse: Decodable {
    let data: [Item]

    struct Item: Decodable {
        let attributes: Attributes

        struct Attributes: Decodable {
            let ttmlLocalizations: String
        }
    }
}

// MARK: - Service Registration

@available(macOS 12.0, *)
extension LyricsProviders.Service where Options == LyricsProviders.EmptyOptions {
    public static let appleMusic = Self(
        id: .appleMusic,
        factory: { _, http in LyricsProviders.AppleMusic(httpClient: http) }
    )
}
