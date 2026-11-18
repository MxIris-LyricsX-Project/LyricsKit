import Testing
import Foundation
@testable import LyricsService

/// How the answers amp-api gives `/v1/me/storefront` read as an
/// authorization status. The status codes are the ones amp-api returned on
/// 2026-11-18: 403 for a forged or missing `media-user-token`, 401 for a
/// broken developer token.
struct AppleMusicAuthorizationProbeTests {
    private static let storefrontBody = Data(
        #"{"data":[{"id":"jp","type":"storefronts","href":"/v1/storefronts/jp"}]}"#.utf8
    )
    private static let forbiddenBody = Data(
        #"{"errors":[{"id":"GQUPHCWGI3CJRN2KMDK37AS4EQ","title":"Forbidden","detail":"Invalid authentication","status":"403","code":"40300"}]}"#.utf8
    )
    private static let serverErrorBody = Data(
        #"{"errors":[{"title":"Internal Server Error","detail":"Try again later","status":"500"}]}"#.utf8
    )

    @Test func storefrontAnswerIsAuthorizedWithTheAccountStorefront() async {
        let status = await AppleMusicAuthorizationProbe.status(
            requestingStorefront: { AppleMusicAPIResponse(statusCode: 200, body: Self.storefrontBody) },
            refreshingDeveloperToken: { Issue.record("An accepted request needs no new developer token.") }
        )
        #expect(status == .authorized(storefront: "jp"))
    }

    @Test func forbiddenAnswerIsDeniedWithoutRefreshingTheDeveloperToken() async {
        let status = await AppleMusicAuthorizationProbe.status(
            requestingStorefront: { AppleMusicAPIResponse(statusCode: 403, body: Self.forbiddenBody) },
            refreshingDeveloperToken: { Issue.record("403 refuses the user token; the developer token was accepted.") }
        )
        #expect(status == .denied)
    }

    @Test func unauthorizedAnswerRefreshesTheDeveloperTokenAndAsksOnceMore() async {
        // amp-api refuses the cached developer token, and accepts the request
        // once a fresh one has been fetched.
        var developerTokenIsFresh = false
        let status = await AppleMusicAuthorizationProbe.status(
            requestingStorefront: {
                developerTokenIsFresh
                    ? AppleMusicAPIResponse(statusCode: 200, body: Self.storefrontBody)
                    : AppleMusicAPIResponse(statusCode: 401, body: Data())
            },
            refreshingDeveloperToken: { developerTokenIsFresh = true }
        )
        #expect(status == .authorized(storefront: "jp"))
    }

    @Test func secondUnauthorizedAnswerCouldNotDetermine() async {
        let status = await AppleMusicAuthorizationProbe.status(
            requestingStorefront: { AppleMusicAPIResponse(statusCode: 401, body: Data()) },
            refreshingDeveloperToken: {}
        )
        #expect(reasonCouldNotDetermine(status) != nil, "A refused developer token says nothing about the user token.")
    }

    @Test func unexpectedStatusCouldNotDetermineWithTheAPIErrorText() async throws {
        let status = await AppleMusicAuthorizationProbe.status(
            requestingStorefront: { AppleMusicAPIResponse(statusCode: 500, body: Self.serverErrorBody) },
            refreshingDeveloperToken: { Issue.record("Only 401 is about the developer token.") }
        )
        let reason = try #require(reasonCouldNotDetermine(status))
        #expect(reason.contains("HTTP 500"))
        #expect(reason.contains("Internal Server Error"))
    }

    @Test func transportFailureCouldNotDetermine() async {
        let status = await AppleMusicAuthorizationProbe.status(
            requestingStorefront: { throw URLError(.notConnectedToInternet) },
            refreshingDeveloperToken: {}
        )
        #expect(reasonCouldNotDetermine(status) != nil)
    }

    @Test func unavailableDeveloperTokenCouldNotDetermine() async throws {
        let status = await AppleMusicAuthorizationProbe.status(
            requestingStorefront: {
                throw AppleMusicError.developerTokenUnavailable("no JWT found in JS bundle /assets/index~x.js")
            },
            refreshingDeveloperToken: {}
        )
        let reason = try #require(reasonCouldNotDetermine(status))
        #expect(reason.contains("no JWT found in JS bundle"))
    }

    @Test func storefrontAnswerWithoutDataCouldNotDetermine() async {
        let status = await AppleMusicAuthorizationProbe.status(
            requestingStorefront: { AppleMusicAPIResponse(statusCode: 200, body: Data(#"{"data":[]}"#.utf8)) },
            refreshingDeveloperToken: {}
        )
        #expect(reasonCouldNotDetermine(status) != nil)
    }

    @available(macOS 12.0, *)
    @Test(arguments: [nil, ""] as [String?])
    func missingOrEmptyTokenIsDenied(mediaUserToken: String?) async {
        let status = await LyricsProviders.Service.appleMusic.authorizationStatus(
            for: .init(mediaUserToken: mediaUserToken)
        )
        #expect(status == .denied)
    }

    private func reasonCouldNotDetermine(_ status: LyricsProviders.AppleMusicAuthorizationStatus) -> String? {
        if case .couldNotDetermine(let reason) = status { return reason }
        return nil
    }
}

/// Asks the real amp-api. Runs only with `LYRICSKIT_LIVE_NETWORK=1`: what 403
/// and 401 mean is Apple's behavior, and this is how to see whether it still
/// holds.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["LYRICSKIT_LIVE_NETWORK"] == "1"))
struct AppleMusicAuthorizationLiveProbes {
    @available(macOS 12.0, *)
    @Test func liveFakeTokenIsDeniedByAmpAPI() async {
        let status = await LyricsProviders.Service.appleMusic.authorizationStatus(
            for: .init(mediaUserToken: "LyricsKitLiveProbeForgedMediaUserToken")
        )
        #expect(status == .denied, "amp-api answered \(status) for a forged media-user-token")
    }
}
