import Foundation

/// A search-request pre-processing plugin.
///
/// A plugin runs *upstream* of the lyrics providers: given the original
/// search request it returns extra requests to search alongside it. A
/// plugin never produces lyrics itself — it only widens the search.
/// `LyricsProviders.Group` applies its plugins once to each incoming
/// request, then runs every provider for the original request plus each
/// request the plugins produced.
///
/// For example, `AppleMusicNameRecoveryPlugin` recovers a track's
/// native-script title/artist — which Apple Music localizes per storefront
/// — and returns a request carrying the recovered name so the third-party
/// providers can match it (issue #17).
public protocol LyricsSearchRequestPlugin: Sendable {

    /// Extra requests to search in addition to `request`.
    ///
    /// Derive returned requests from `request` with
    /// ``LyricsSearchRequest/derived(searchTerm:)`` so their results stay
    /// attributed to the originating search session. Return an empty array
    /// to add nothing; a plugin must finish empty rather than throw, so a
    /// plugin failure can never disrupt the original search.
    func additionalRequests(for request: LyricsSearchRequest) async -> [LyricsSearchRequest]
}
