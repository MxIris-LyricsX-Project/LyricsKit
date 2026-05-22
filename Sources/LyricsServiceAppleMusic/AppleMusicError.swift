import Foundation

/// Errors surfaced by the Apple Music transport and catalog layers.
public enum AppleMusicError: Error, Sendable {
    /// `MusicKit` is not available (web-session transport: not on the page).
    case musicKitUnavailable
    /// The underlying request reported an error; carries a description.
    case api(String)
    /// The Apple Music API returned JSON that did not match the expected shape.
    case unexpectedResponse
}
