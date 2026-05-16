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
        private let factory: @Sendable (Options) -> LyricsProvider

        init(id: ServiceID, factory: @escaping @Sendable (Options) -> LyricsProvider) {
            self.id = id
            self.factory = factory
        }

        public func create(_ options: Options = .init()) -> LyricsProvider {
            factory(options)
        }
    }
}

extension LyricsProviders.Service where Options == LyricsProviders.EmptyOptions {
    public static let netease = Self(id: .netease, factory: { _ in LyricsProviders.NetEase() })
    public static let qq      = Self(id: .qq,      factory: { _ in LyricsProviders.QQMusic() })
    public static let kugou   = Self(id: .kugou,   factory: { _ in LyricsProviders.Kugou() })
    public static let lrclib  = Self(id: .lrclib,  factory: { _ in LyricsProviders.LRCLIB() })
}
