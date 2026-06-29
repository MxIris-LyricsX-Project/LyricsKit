import Foundation
import os

// `AppleMusicError` lives in AppleMusicError.swift.
//
// The Route B catalog path uses `MusicDataRequest` (see AppleMusicCatalog)
// and does NOT use this class — it needs no token and no sign-in.
//
// This class powers Route A (official syllable-lyrics): that endpoint is
// not served by `MusicDataRequest` (returns HTML / 401). Instead, requests
// are issued directly to `amp-api.music.apple.com` over `URLSession`,
// carrying:
//
//   1. an `Authorization: Bearer <developer-token>` — the JWT the Apple
//      Music web player ships in its own JS bundle (issuer `AMPWebPlay`,
//      ~35-day TTL, fetched on demand and cached for the process lifetime
//      by `AppleMusicDeveloperTokenCache`);
//   2. a `media-user-token: <user-token>` — pasted by the user once in
//      preferences (this proves the active Apple Music subscription),
//      passed in at construction time;
//   3. `Origin: https://music.apple.com` + `Referer: …/` — the developer
//      token's `root_https_origin` claim restricts which origins amp-api
//      will accept it from.
//
// No `WKWebView`, no MusicKit JS runtime, no MusicKit App Service /
// developer team registration.

/// A per-provider Apple Music amp-api session over `URLSession`.
///
/// Configuration (`mediaUserToken` / `storefrontOverride` / `languageOverride`)
/// is injected at construction time and is then immutable for the session's
/// lifetime — there is no global `shared` instance anymore. The expensive,
/// process-global piece (developer-token scrape + cache) is owned by
/// `AppleMusicDeveloperTokenCache` so rebuilding the provider does not
/// re-scrape the web player's JS bundle.
@available(macOS 12.0, *)
actor AppleMusicSession {

    // MARK: - Injected configuration

    let mediaUserToken: String?
    let storefrontOverride: String?
    let languageOverride: String?

    // MARK: - Per-instance state

    /// Last result of the lightweight authorization probe — recomputed on
    /// demand the first time `isAuthorized()` is called.
    private var authorizedCache: Bool?

    private let urlSession: URLSession

    init(
        mediaUserToken: String? = nil,
        storefrontOverride: String? = nil,
        languageOverride: String? = nil
    ) {
        self.mediaUserToken = mediaUserToken
        self.storefrontOverride = storefrontOverride
        self.languageOverride = languageOverride

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = [
            "User-Agent": AppleMusicUserAgent.value,
            "Accept": "*/*",
            "Accept-Language": "en-US,en;q=0.9",
        ]
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        urlSession = URLSession(configuration: configuration)
    }

    // MARK: - Authorization probe

    /// Whether amp-api accepts the configured `media-user-token`.
    ///
    /// Cached per-instance. The probe hits `/v1/me/storefront` once, so
    /// later `musicAPI()` calls for user-context paths can short-circuit
    /// on failure (LyricsX uses this to decide whether to mount the
    /// Apple Music provider at all).
    func isAuthorized() async -> Bool {
        if let cached = authorizedCache { return cached }
        guard mediaUserToken != nil else {
            authorizedCache = false
            return false
        }
        do {
            _ = try await musicAPI("/v1/me/storefront")
            authorizedCache = true
            return true
        } catch {
            Logger.AppleMusic.info(
                "authorization probe failed: \(String(describing: error), privacy: .public)")
            authorizedCache = false
            return false
        }
    }

    // MARK: - amp-api

    /// Issue an amp-api GET and return the raw response body.
    ///
    /// - Parameter path: an amp-api path, e.g.
    ///   `/v1/catalog/cn/songs/535824738/syllable-lyrics?l=zh-Hans`.
    /// - Returns: the raw response body. The caller is responsible for
    ///   JSON decoding.
    /// - Throws: `AppleMusicError.api` on transport failure or non-2xx
    ///   response (carries the API's error description when available),
    ///   `AppleMusicError.unexpectedResponse` on malformed URLs.
    func musicAPI(_ path: String) async throws -> Data {
        let developerToken = try await AppleMusicDeveloperTokenCache.shared.ensureToken()
        guard let url = URL(string: "https://amp-api.music.apple.com" + path) else {
            throw AppleMusicError.unexpectedResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(developerToken)", forHTTPHeaderField: "Authorization")
        if let userToken = mediaUserToken {
            request.setValue(userToken, forHTTPHeaderField: "media-user-token")
        }
        // The developer token's `root_https_origin` claim restricts which
        // sites amp-api accepts it from. Without these, every request 403s.
        request.setValue("https://music.apple.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.apple.com/", forHTTPHeaderField: "Referer")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppleMusicError.unexpectedResponse
        }

        if (200..<300).contains(httpResponse.statusCode) {
            return data
        }

        // Non-2xx: 401/403 usually means the user token expired or the
        // developer token rolled. Drop both caches so the next call
        // refetches the developer token and re-probes authorization.
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            await AppleMusicDeveloperTokenCache.shared.invalidate()
            authorizedCache = nil
        }
        let description = AppleMusicAPIErrorParser.describe(data: data, status: httpResponse.statusCode)
        throw AppleMusicError.api(description)
    }
}

// MARK: - Process-level developer-token cache

/// Process-wide cache for the public Apple Music web-player developer token.
///
/// The token is not user-specific (it ships in the public JS bundle, see
/// `fetchDeveloperToken()`) and has a ~35-day TTL, so a single cache shared
/// by every `AppleMusicSession` instance avoids redundant scrapes whenever
/// the provider is rebuilt (e.g. preferences change).
@available(macOS 12.0, *)
actor AppleMusicDeveloperTokenCache {

    static let shared = AppleMusicDeveloperTokenCache()

    private var cached: CachedDeveloperToken?
    private let urlSession: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = [
            "User-Agent": AppleMusicUserAgent.value,
            "Accept": "*/*",
            "Accept-Language": "en-US,en;q=0.9",
        ]
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        urlSession = URLSession(configuration: configuration)
    }

    /// Return a non-expired developer token, fetching one if needed.
    func ensureToken() async throws -> String {
        if let cached, cached.expiresAt > Date().addingTimeInterval(60 * 60) {
            // Still has at least 1h to live — reuse.
            return cached.value
        }
        let fresh = try await fetchDeveloperToken()
        cached = fresh
        let daysLeft = Int(fresh.expiresAt.timeIntervalSinceNow / 86400)
        Logger.AppleMusic.debug(
            "fetched developer token, exp ~\(daysLeft, privacy: .public) days from now")
        return fresh.value
    }

    /// Drop the cached token, e.g. after amp-api returns 401/403.
    func invalidate() {
        cached = nil
    }

    /// Scrape the developer token from the public Apple Music web player.
    /// The token is embedded as a `qc="ey..."` assignment in the main JS
    /// bundle, whose path is in turn referenced from the landing page HTML.
    /// If Apple mangles the variable name in a future build, fall back to
    /// pattern-matching any long JWT-shaped string in the bundle.
    private func fetchDeveloperToken() async throws -> CachedDeveloperToken {
        let html = try await fetch(URL(string: "https://music.apple.com")!)
        guard let htmlString = String(data: html, encoding: .utf8) else {
            throw AppleMusicError.developerTokenUnavailable("landing page is not UTF-8")
        }
        guard let bundlePath = AppleMusicTokenScraper.findJSBundlePath(in: htmlString) else {
            throw AppleMusicError.developerTokenUnavailable(
                "no /assets/index~*.js reference found in music.apple.com")
        }
        let bundleURL = URL(string: "https://music.apple.com" + bundlePath)!
        let bundle = try await fetch(bundleURL)
        guard let bundleString = String(data: bundle, encoding: .utf8) else {
            throw AppleMusicError.developerTokenUnavailable("JS bundle is not UTF-8")
        }
        guard let raw = AppleMusicTokenScraper.findDeveloperToken(in: bundleString) else {
            throw AppleMusicError.developerTokenUnavailable(
                "no JWT found in JS bundle \(bundlePath)")
        }
        guard let (issuedAt, expiresAt) = AppleMusicTokenScraper.decodeJWTValidity(raw) else {
            throw AppleMusicError.developerTokenUnavailable("JWT payload is malformed")
        }
        return CachedDeveloperToken(value: raw, issuedAt: issuedAt, expiresAt: expiresAt)
    }

    /// HTTP GET helper that does NOT add amp-api auth headers — used by
    /// the developer-token fetch, which targets `music.apple.com`
    /// directly rather than the API host.
    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(AppleMusicUserAgent.value, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw AppleMusicError.api(
                "GET \(url.absoluteString) failed: HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        return data
    }
}

// MARK: - Static parsing helpers

private enum AppleMusicTokenScraper {

    /// Extract a path like `/assets/index~299c09aac6.js` from the landing
    /// page HTML. The hash in the filename rolls with every web-player
    /// release.
    static func findJSBundlePath(in html: String) -> String? {
        do {
            let regex = try NSRegularExpression(
                pattern: #"/assets/index~[A-Za-z0-9]+\.js"#)
            let range = NSRange(html.startIndex..., in: html)
            guard let match = regex.firstMatch(in: html, range: range),
                  let stringRange = Range(match.range, in: html)
            else { return nil }
            return String(html[stringRange])
        } catch {
            return nil
        }
    }

    /// Extract the developer-token JWT from the JS bundle. Prefer the
    /// known `qc="..."` assignment used by current builds; fall back to a
    /// JWT-shape scan so a webpack rename doesn't break the feature.
    static func findDeveloperToken(in js: String) -> String? {
        // Apple's current bundle: `qc="eyJ...";` (variable name may roll).
        let primaryPattern = #"qc\s*=\s*"(eyJ[A-Za-z0-9_.-]{100,})""#
        if let primary = firstCapture(in: js, pattern: primaryPattern) {
            return primary
        }
        // Fallback: any sufficiently long JWT-shaped literal between quotes.
        let fallbackPattern = #""(eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)""#
        return firstCapture(in: js, pattern: fallbackPattern)
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges >= 2,
              let captureRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[captureRange])
    }

    /// Decode `iat` / `exp` from a JWT without verifying the signature
    /// (we just need to know how long the token is good for; Apple's
    /// servers do the cryptographic verification).
    static func decodeJWTValidity(_ jwt: String) -> (iat: Date, exp: Date)? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        let payload = String(parts[1])
        guard let data = base64URLDecode(payload),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        guard let iat = (dict["iat"] as? NSNumber)?.doubleValue,
              let exp = (dict["exp"] as? NSNumber)?.doubleValue
        else { return nil }
        return (Date(timeIntervalSince1970: iat), Date(timeIntervalSince1970: exp))
    }

    /// Base64URL → bytes, padding the input to the next multiple of 4.
    private static func base64URLDecode(_ string: String) -> Data? {
        var normalized = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder > 0 {
            normalized.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: normalized)
    }
}

private enum AppleMusicAPIErrorParser {
    /// Pull a human-readable error string out of amp-api's `{errors:[…]}`
    /// envelope, falling back to the status code when the body is empty.
    static func describe(data: Data, status: Int) -> String {
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errors = dict["errors"] as? [[String: Any]],
           let first = errors.first {
            let title = first["title"] as? String ?? "Error"
            let detail = first["detail"] as? String ?? ""
            return "HTTP \(status): \(title) — \(detail)"
        }
        return "HTTP \(status)"
    }
}

private enum AppleMusicUserAgent {
    /// Apple's web player only serves to a Safari-on-macOS UA — this is
    /// what music.apple.com renders for in a real session.
    static let value =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
}

// MARK: - Cached developer token

private struct CachedDeveloperToken: Sendable {
    let value: String
    let issuedAt: Date
    let expiresAt: Date
}

// MARK: - Logger

@available(macOS 11.0, *)
extension Logger {
    static let AppleMusic = Logger(
        subsystem: "LyricsKit.AppleMusic", category: "Session")
}
