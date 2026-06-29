import Foundation
import MusicKit

/// One song from the Apple Music catalog, flattened to the fields Route B
/// needs. `name` / `artistName` are localized by the *storefront* they were
/// fetched from.
public struct AppleMusicCatalogSong: Sendable, Equatable {
    public let id: String
    public let name: String
    public let artistName: String
    public let albumName: String?
    public let isrc: String?
    public let durationInMillis: Int?
}

/// A thin wrapper over the Apple Music catalog API.
///
/// Requests go through MusicKit's `MusicDataRequest`, which injects the
/// developer token (and the user token, once `MusicAuthorization` is granted)
/// automatically — no WKWebView and no manual token handling. Requires the
/// MusicKit App Service to be enabled on the host app's App ID.
@available(macOS 12.0, *)
public struct AppleMusicCatalog: Sendable {

    public init() {}

    /// The signed-in account's storefront id, e.g. `cn`, `tw`, `jp`.
    public func storefront() async throws -> String {
        let data = try await get(path: "/v1/me/storefront")
        let response = try JSONDecoder().decode(StorefrontResponse.self, from: data)
        guard let id = response.data.first?.id else {
            throw AppleMusicError.unexpectedResponse
        }
        return id
    }

    /// Search a storefront's catalog for songs matching a free-text term.
    public func search(
        term: String, storefront: String, limit: Int = 10
    ) async throws -> [AppleMusicCatalogSong] {
        let data = try await get(
            path: "/v1/catalog/\(storefront)/search",
            queryItems: [
                URLQueryItem(name: "types", value: "songs"),
                URLQueryItem(name: "term", value: term),
                URLQueryItem(name: "limit", value: String(limit)),
            ])
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        return (response.results.songs?.data ?? []).map(\.flattened)
    }

    /// Look up a single catalog song by its adamID within a storefront.
    public func song(id: String, storefront: String) async throws -> AppleMusicCatalogSong {
        let data = try await get(path: "/v1/catalog/\(storefront)/songs/\(id)")
        let response = try JSONDecoder().decode(SongListResponse.self, from: data)
        guard let song = response.data.first else {
            throw AppleMusicError.unexpectedResponse
        }
        return song.flattened
    }

    /// Look up catalog songs sharing an ISRC within a storefront.
    ///
    /// ISRC is the only storefront-independent key for a recording, so this is
    /// how Route B locates the same song in its native-script storefront.
    public func songs(isrc: String, storefront: String) async throws -> [AppleMusicCatalogSong] {
        let data = try await get(
            path: "/v1/catalog/\(storefront)/songs",
            queryItems: [URLQueryItem(name: "filter[isrc]", value: isrc)])
        let response = try JSONDecoder().decode(SongListResponse.self, from: data)
        return response.data.map(\.flattened)
    }

    /// Execute an Apple Music API GET through MusicKit and return the raw body.
    /// `MusicDataRequest` attaches the developer/user tokens itself.
    private func get(path: String, queryItems: [URLQueryItem] = []) async throws -> Data {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.music.apple.com"
        components.path = path
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw AppleMusicError.unexpectedResponse
        }
        // Bound each catalog call so a slow network can't keep a Route B
        // search alive for the URLSession default of 60s.
        var urlRequest = URLRequest(url: url)
        urlRequest.timeoutInterval = 10
        return try await MusicDataRequest(urlRequest: urlRequest).response().data
    }
}

// MARK: - Apple Music API wire models

private struct StorefrontResponse: Decodable {
    let data: [Storefront]

    struct Storefront: Decodable {
        let id: String
    }
}

/// `GET .../songs` and `GET .../songs/{id}` both return `{ "data": [song] }`.
private struct SongListResponse: Decodable {
    let data: [CatalogSongResource]
}

/// `GET .../search` nests the songs under `results.songs.data`.
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
