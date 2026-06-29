import Foundation

/// Errors surfaced by the Apple Music transport and catalog layers.
public enum AppleMusicError: Error, Sendable {
    /// `MusicKit` is not available (Route B / `MusicDataRequest` transport).
    case musicKitUnavailable
    /// The underlying request reported an error; carries a description.
    case api(String)
    /// The Apple Music API returned JSON that did not match the expected shape.
    case unexpectedResponse
    /// Route A could not scrape a developer token from the public web
    /// player (Apple changed the HTML or JS structure). Carries a hint.
    case developerTokenUnavailable(String)
}
