import Foundation
import os
import LyricsService
import MusicKit

/// Route B — a lyrics-search *plugin*, not a lyrics source.
///
/// Apple Music localizes a track's title/artist by storefront, so the
/// now-playing name LyricsX sees can be a romanization or English
/// translation (issue #17: 「雨のメヌエット」→「Ame No Minuet」). Searching the
/// third-party providers with that mismatched name then fails.
///
/// For an Apple Music track this plugin:
///
/// 1. resolves the now-playing track to an Apple Music adamID — either the
///    explicit id passed in `userInfo`, or by searching the user's
///    storefront catalog by name and matching on duration;
/// 2. resolves the adamID to the song's ISRC;
/// 3. uses the ISRC (the only storefront-independent key) to look the
///    recording up in its native-script storefront, recovering the
///    original title/artist;
/// 4. returns a request — derived from the original so results stay
///    attributed to the same search session — for each recovered name, so
///    `LyricsProviders.Group` re-runs the third-party providers with it.
///
/// It only ever *adds* requests. When the track is not from Apple Music,
/// when Apple Music access is not authorized, or on any failure it returns
/// an empty array — the direct search is unaffected.
@available(macOS 12.0, *)
public struct AppleMusicNameRecoveryPlugin: LyricsSearchRequestPlugin {

    /// `userInfo` flag (`"1"`) set by LyricsX when the now-playing track is
    /// from Apple Music. Route B only runs for those tracks.
    public static let appleMusicTrackUserInfoKey = "appleMusicNowPlaying"

    /// `userInfo` key for an already-known Apple Music adamID. When present
    /// it is used directly, skipping the catalog name search.
    public static let adamIDUserInfoKey = "appleMusicAdamID"

    /// A catalog song matches the now-playing track when their durations
    /// are within this many seconds of each other.
    private static let durationTolerance: TimeInterval = 4

    private let catalog = AppleMusicCatalog()

    public init() {}

    // MARK: - LyricsSearchRequestPlugin

    public func additionalRequests(
        for request: LyricsSearchRequest
    ) async -> [LyricsSearchRequest] {
        // Catalog requests need a developer token, which MusicKit only
        // vends once the user has authorized Apple Music access.
        guard MusicAuthorization.currentStatus == .authorized else {
            return []
        }
        do {
            let names = try await recoverNativeNames(for: request)
            return names.map { name in
                request.derived(searchTerm: .info(title: name.title, artist: name.artist))
            }
        } catch {
            // A superseded search (track change, stream teardown) cancels the
            // in-flight catalog requests; MusicKit surfaces that as a URL -999
            // error, not a Swift CancellationError. Either way it is expected.
            if Task.isCancelled || error is CancellationError {
                return []
            }
            Self.log.error("name recovery failed, skipping: \(String(describing: error))")
            return []
        }
    }

    // MARK: - Recovery pipeline

    /// now-playing track -> ISRC -> native-script `(title, artist)` variants
    /// that differ from the name LyricsX already searched with.
    private func recoverNativeNames(
        for request: LyricsSearchRequest
    ) async throws -> [RecoveredName] {
        let userStorefront = try await catalog.storefront()

        guard let song = try await resolveSong(for: request, storefront: userStorefront) else {
            return []
        }
        guard let isrc = song.isrc, !isrc.isEmpty else {
            return []
        }

        // The user's own storefront is *not* excluded: the now-playing name
        // LyricsX sees is localized by the Apple Music app's display language
        // (the system language), whereas a direct catalog query returns the
        // storefront's own language — so even the user's storefront yields a
        // name worth recovering. Excluding it also emptied the target list
        // outright for a song whose ISRC country is the user's storefront.
        let targets = nativeStorefronts(forISRC: isrc)
        guard !targets.isEmpty else {
            return []
        }

        // Query the candidate storefronts concurrently; one failing
        // storefront must not sink the others.
        let catalog = self.catalog
        var collected: [RecoveredName] = []
        await withTaskGroup(of: [AppleMusicCatalogSong].self) { group in
            for storefront in targets {
                group.addTask {
                    (try? await catalog.songs(isrc: isrc, storefront: storefront)) ?? []
                }
            }
            for await songs in group {
                for candidate in songs {
                    collected.append(
                        RecoveredName(title: candidate.name, artist: candidate.artistName))
                }
            }
        }

        return distinctVariants(collected, differingFrom: request.searchTerm)
    }

    /// Resolve the now-playing track to its catalog song in `storefront`.
    ///
    /// An explicit adamID from `userInfo` is looked up by id; otherwise a
    /// catalog name search matched on duration is used — and that search
    /// result already carries the ISRC, so the search path needs no extra
    /// by-id lookup.
    private func resolveSong(
        for request: LyricsSearchRequest, storefront: String
    ) async throws -> AppleMusicCatalogSong? {
        if let explicitAdamID = request.userInfo[Self.adamIDUserInfoKey], !explicitAdamID.isEmpty {
            return try await catalog.song(id: explicitAdamID, storefront: storefront)
        }
        let candidates = try await catalog.search(
            term: request.searchTerm.description, storefront: storefront)
        return bestMatch(candidates, duration: request.duration)
    }

    /// Pick the catalog song whose duration is closest to — and within
    /// tolerance of — the now-playing track. With no usable duration, take
    /// the first result.
    private func bestMatch(
        _ songs: [AppleMusicCatalogSong], duration: TimeInterval
    ) -> AppleMusicCatalogSong? {
        guard duration > 0 else {
            return songs.first
        }
        return songs
            .compactMap { song -> (song: AppleMusicCatalogSong, delta: TimeInterval)? in
                guard let millis = song.durationInMillis else { return nil }
                let delta = abs(TimeInterval(millis) / 1000 - duration)
                return delta <= Self.durationTolerance ? (song, delta) : nil
            }
            .min { $0.delta < $1.delta }?
            .song
    }

    /// Keep distinct `(title, artist)` variants that differ from what
    /// LyricsX already searched — re-searching an identical name is wasted
    /// work. The pair is compared because a track's title is often stable
    /// across storefronts while the artist is romanized/transliterated
    /// (晴天 stays 晴天, but 周杰伦 -> 周杰倫 / Jay Chou / 주걸륜).
    private func distinctVariants(
        _ names: [RecoveredName], differingFrom original: LyricsSearchRequest.SearchTerm
    ) -> [RecoveredName] {
        let originalTitle = original.titleOnly
        let originalArtist: String
        if case let .info(_, artist) = original {
            originalArtist = artist
        } else {
            originalArtist = ""
        }

        var seen: Set<RecoveredName> = []
        return names.filter { name in
            guard !name.title.isEmpty else {
                return false
            }
            let sameAsOriginal =
                name.title.caseInsensitiveCompare(originalTitle) == .orderedSame
                && name.artist.caseInsensitiveCompare(originalArtist) == .orderedSame
            guard !sameAsOriginal else {
                return false
            }
            return seen.insert(name).inserted
        }
    }

    /// Map an ISRC to the storefront(s) that serve its native-script
    /// metadata. The first two ISRC characters are the registrant country.
    private func nativeStorefronts(forISRC isrc: String) -> [String] {
        let country = String(isrc.prefix(2)).uppercased()
        let cjkStorefronts = ["TW": "tw", "JP": "jp", "HK": "hk", "CN": "cn", "KR": "kr"]
        if let storefront = cjkStorefronts[country] {
            return [storefront]
        }
        // Unknown / non-CJK registrant: fan out across the CJK storefronts,
        // since issue #17 is about CJK titles being romanized/translated.
        return ["jp", "cn", "tw", "hk", "kr"]
    }

    private struct RecoveredName: Hashable, Sendable {
        let title: String
        let artist: String
    }

    private static let log = Logger(
        subsystem: "LyricsKit.AppleMusic", category: "NameRecovery")
}
