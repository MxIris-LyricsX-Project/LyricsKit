import Foundation
import WebKit

// `AppleMusicError` lives in AppleMusicError.swift.
//
// NOTE: as of the MusicKit transport switch, the Route B catalog path uses
// `MusicDataRequest` (see AppleMusicCatalog) and does NOT use this class.
// `AppleMusicWebSession` is kept for a possible future Route A (official
// syllable-lyrics), whose user-token endpoint may still need the web session.

/// A persistent, signed-in `music.apple.com` session that calls the private
/// amp-api from *inside* the page.
///
/// Native `URLSession` requests to amp-api fail with HTTP 401 — they lack the
/// browser's session cookies. Routing the request through the web player's own
/// `MusicKit.getInstance().api.music(path)` carries the correct developer
/// token, user token, cookies and origin, and refreshes the token
/// automatically. This class owns the `WKWebView` hosting that page.
///
/// The user signs in once with their own Apple ID; the persistent website data
/// store keeps that session across launches.
@available(macOS 12.0, *)
@MainActor
public final class AppleMusicWebSession {

    /// Shared session, used by the Apple Music providers and the sign-in UI.
    public static let shared = AppleMusicWebSession()

    /// The web view hosting `music.apple.com`. The host app presents this for
    /// the one-time sign-in and may keep it alive (off-screen) afterwards.
    public let webView: WKWebView

    private var didStartLoading = false

    public init() {
        let configuration = WKWebViewConfiguration()
        // The default website data store is persistent: the sign-in survives
        // relaunches, so the user only authenticates once.
        webView = WKWebView(frame: .zero, configuration: configuration)
        // music.apple.com only serves the full web player to a desktop browser.
        webView.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    }

    /// Navigate to `music.apple.com` if it has not been loaded yet. Safe to
    /// call repeatedly; only the first call triggers a navigation.
    public func startLoadingIfNeeded() {
        guard !didStartLoading, let url = URL(string: "https://music.apple.com") else {
            return
        }
        didStartLoading = true
        webView.load(URLRequest(url: url))
    }

    /// Whether the web player reports a completed Apple Music sign-in.
    public func isAuthorized() async -> Bool {
        let probe = """
        try {
            const music = MusicKit.getInstance();
            return !!(music && music.isAuthorized && music.musicUserToken);
        } catch (error) {
            return false;
        }
        """
        let result = try? await webView.callAsyncJavaScript(
            probe, arguments: [:], in: nil, contentWorld: .page)
        return (result as? Bool) ?? false
    }

    /// Call an amp-api path through the web player's `MusicKit` instance and
    /// return the raw response body as JSON `Data`.
    ///
    /// - Parameter path: an amp-api path, e.g. `/v1/catalog/cn/songs/535824738`.
    public func musicAPI(_ path: String) async throws -> Data {
        // Runs in the page's content world so `MusicKit` is in scope. The
        // result is double-encoded — an `{ok,body,error}` envelope whose
        // `body` is the response JSON as a string — so a JS-side error can be
        // reported without it looking like a malformed response.
        let functionBody = """
        const music = MusicKit.getInstance();
        if (!music || !music.api || typeof music.api.music !== 'function') {
            return JSON.stringify({ ok: false, error: 'MusicKit not ready' });
        }
        try {
            const response = await music.api.music(path);
            const payload = (response && response.data !== undefined)
                ? response.data
                : response;
            return JSON.stringify({ ok: true, body: JSON.stringify(payload) });
        } catch (error) {
            return JSON.stringify({
                ok: false,
                error: String((error && error.message) ? error.message : error),
            });
        }
        """

        let rawResult: Any?
        do {
            rawResult = try await webView.callAsyncJavaScript(
                functionBody, arguments: ["path": path], in: nil, contentWorld: .page)
        } catch {
            throw AppleMusicError.api(error.localizedDescription)
        }

        guard let jsonString = rawResult as? String,
              let envelopeData = jsonString.data(using: .utf8),
              let envelope = try? JSONSerialization.jsonObject(with: envelopeData) as? [String: Any]
        else {
            throw AppleMusicError.unexpectedResponse
        }

        if envelope["ok"] as? Bool == true {
            guard let bodyString = envelope["body"] as? String,
                  let bodyData = bodyString.data(using: .utf8)
            else {
                throw AppleMusicError.unexpectedResponse
            }
            return bodyData
        }

        let message = envelope["error"] as? String ?? "unknown error"
        if message == "MusicKit not ready" {
            throw AppleMusicError.musicKitUnavailable
        }
        throw AppleMusicError.api(message)
    }
}
