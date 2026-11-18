import Foundation

/// One answer from amp-api: its HTTP status code and body, whatever the code.
struct AppleMusicAPIResponse: Sendable {
    let statusCode: Int
    let body: Data
}

/// Turns amp-api's answer to `/v1/me/storefront` into an
/// `AppleMusicAuthorizationStatus`.
///
/// The request and the developer-token refresh are passed in, so the rules
/// can be checked without a network.
enum AppleMusicAuthorizationProbe {
    static func status(
        requestingStorefront requestStorefront: () async throws -> AppleMusicAPIResponse,
        refreshingDeveloperToken refreshDeveloperToken: () async -> Void
    ) async -> LyricsProviders.AppleMusicAuthorizationStatus {
        for attempt in 1...2 {
            let response: AppleMusicAPIResponse
            do {
                response = try await requestStorefront()
            } catch {
                return .couldNotDetermine(reason: describe(error))
            }
            switch response.statusCode {
            case 200..<300:
                guard let storefront = AppleMusicStorefrontResponse.storefrontIdentifier(in: response.body) else {
                    return .couldNotDetermine(reason: "amp-api's storefront response has no storefront")
                }
                return .authorized(storefront: storefront)
            case 403:
                // The developer token was accepted; the user token was not.
                return .denied
            case 401 where attempt == 1:
                // The developer token was refused — it may have rolled since
                // it was cached. Fetch a new one and ask once more.
                await refreshDeveloperToken()
            case 401:
                return .couldNotDetermine(reason: "amp-api refused the web player's developer token")
            default:
                return .couldNotDetermine(
                    reason: AppleMusicAPIErrorParser.describe(data: response.body, status: response.statusCode)
                )
            }
        }
        preconditionFailure("The second attempt always returns.")
    }

    private static func describe(_ error: Error) -> String {
        if let appleMusicError = error as? AppleMusicError {
            switch appleMusicError {
            case .developerTokenUnavailable(let hint):
                return "couldn't fetch the web player's developer token: \(hint)"
            case .api(let description):
                return description
            case .musicKitUnavailable, .unexpectedResponse:
                break
            }
        }
        return error.localizedDescription
    }
}
