import Foundation

public protocol LyricsProviderOptions: Sendable {
    init()
}

extension LyricsProviders {
    public struct EmptyOptions: LyricsProviderOptions {
        public init() {}
    }

    public enum ServiceID: String, CaseIterable, Hashable, Sendable {
        case netease
        case qq
        case kugou
        case musixmatch
        case lrclib
        case appleMusic

        public var displayName: String {
            switch self {
            case .netease: return "NetEase"
            case .qq: return "QQMusic"
            case .kugou: return "Kugou"
            case .musixmatch: return "Musixmatch"
            case .lrclib: return "LRCLIB"
            case .appleMusic: return "Apple Music"
            }
        }
    }

    public struct Service<Options: LyricsProviderOptions>: Sendable {
        public let id: ServiceID
        public var displayName: String { id.displayName }
        private let factory: @Sendable (Options, HTTPClient) -> LyricsProvider

        // `public` so add-on targets (e.g. LyricsServiceAppleMusic) can register
        // their own services without having to live inside LyricsService.
        public init(id: ServiceID, factory: @escaping @Sendable (Options, HTTPClient) -> LyricsProvider) {
            self.id = id
            self.factory = factory
        }

        public func create(
            _ options: Options = .init(),
            httpClient: HTTPClient = URLSessionHTTPClient.shared
        ) -> LyricsProvider {
            factory(options, httpClient)
        }
    }
}

extension LyricsProviders.Service where Options == LyricsProviders.EmptyOptions {
    public static let netease = Self(id: .netease, factory: { _, http in LyricsProviders.NetEase(httpClient: http) })
    public static let qq      = Self(id: .qq,      factory: { _, http in LyricsProviders.QQMusic(httpClient: http) })
    public static let kugou   = Self(id: .kugou,   factory: { _, http in LyricsProviders.Kugou(httpClient: http) })
    public static let lrclib  = Self(id: .lrclib,  factory: { _, http in LyricsProviders.LRCLIB(httpClient: http) })
}

extension LyricsProviders.Service where Options == LyricsProviders.MusixmatchOptions {
    public static let musixmatch = Self(
        id: .musixmatch,
        factory: { options, http in LyricsProviders.Musixmatch(options: options, httpClient: http) }
    )
}

@available(macOS 12.0, *)
extension LyricsProviders.Service where Options == LyricsProviders.AppleMusicOptions {
    public static let appleMusic = Self(
        id: .appleMusic,
        factory: { options, http in LyricsProviders.AppleMusic(options: options, httpClient: http) }
    )
}
