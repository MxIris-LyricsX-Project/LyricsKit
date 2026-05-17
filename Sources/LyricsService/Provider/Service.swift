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

        public var displayName: String {
            switch self {
            case .netease: return "NetEase"
            case .qq: return "QQMusic"
            case .kugou: return "Kugou"
            case .musixmatch: return "Musixmatch"
            case .lrclib: return "LRCLIB"
            }
        }
    }

    public struct Service<Options: LyricsProviderOptions>: Sendable {
        public let id: ServiceID
        public var displayName: String { id.displayName }
        private let factory: @Sendable (Options, HTTPClient) -> LyricsProvider

        init(id: ServiceID, factory: @escaping @Sendable (Options, HTTPClient) -> LyricsProvider) {
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
