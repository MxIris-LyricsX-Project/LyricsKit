import Foundation

extension LyricsProviders {
    public enum Service: CaseIterable, Equatable, Hashable {
        case qq
        case netease
        case kugou
        case musixmatch
        case lrclib
        case spotify

        public var displayName: String {
            switch self {
            case .netease: return "Netease"
            case .qq: return "QQMusic"
            case .kugou: return "Kugou"
            case .musixmatch: return "Musixmatch"
            case .lrclib: return "LRCLIB"
            case .spotify: return "Spotify"
            }
        }

        public var requiresAuthentication: Bool {
            switch self {
            case .spotify:
                return true
            case .qq,
                 .netease,
                 .kugou,
                 .musixmatch,
                 .lrclib:
                return false
            }
        }

        public static var noAuthenticationRequiredServices: [Service] {
            [
                .qq,
                .netease,
                .kugou,
                .musixmatch,
                .lrclib,
            ]
        }

        public static var authenticationRequiredServices: [Service] {
            [
                .spotify,
            ]
        }
    }
}

extension LyricsProviders.Service {
    public func create() -> LyricsProvider {
        switch self {
        case .netease: return LyricsProviders.NetEase()
        case .qq: return LyricsProviders.QQMusic()
        case .kugou: return LyricsProviders.Kugou()
        case .musixmatch: return LyricsProviders.Musixmatch()
        case .spotify: return LyricsProviders.Spotify()
        case .lrclib: return LyricsProviders.LRCLIB()
        }
    }

    public func create(with authManager: AuthenticationManager?) async throws -> LyricsProvider {
        switch self {
        case .spotify:
            guard let authManager = authManager else {
                throw AuthenticationError.notAuthenticated
            }
            let provider = LyricsProviders.Spotify()
            provider.authenticationManager = authManager
            return provider
        case .netease,
             .qq,
             .kugou,
             .musixmatch,
             .lrclib:
            return create()
        }
    }
}
