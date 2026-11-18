import Foundation

extension LyricsProviders {
    /// What Apple Music's amp-api made of a `media-user-token`.
    ///
    /// The answer comes from `/v1/me/storefront`, the endpoint the provider
    /// itself asks first: HTTP 403 there means the user token was refused,
    /// HTTP 401 means the web player's developer token was (verified against
    /// amp-api on 2026-11-18).
    public enum AppleMusicAuthorizationStatus: Hashable, Sendable {
        /// amp-api accepted the token. `storefront` is the account's
        /// storefront identifier, such as `"jp"`.
        case authorized(storefront: String)
        /// amp-api refused the token (HTTP 403): it is mistyped, expired, or
        /// belongs to a session that signed out. A missing or empty token is
        /// also `denied`, without a request.
        case denied
        /// The check reached no verdict: no network, the web player's
        /// developer token could not be fetched or was refused twice, or
        /// amp-api answered something unexpected. `reason` is for logs and
        /// tooltips, not for matching.
        case couldNotDetermine(reason: String)
    }
}

@available(macOS 12.0, *)
extension LyricsProviders.Service where Options == LyricsProviders.AppleMusicOptions {
    /// Asks amp-api whether it accepts `options.mediaUserToken`, the way the
    /// provider made by `create(_:)` will use it.
    ///
    /// Each call asks afresh; nothing is cached between calls.
    public func authorizationStatus(for options: Options) async -> LyricsProviders.AppleMusicAuthorizationStatus {
        await AppleMusicSession(mediaUserToken: options.mediaUserToken).authorizationStatus()
    }
}
