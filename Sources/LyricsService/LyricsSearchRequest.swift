import Foundation

public struct LyricsSearchRequest: Equatable, Sendable, Identifiable {

    /// Identity of one logical search session.
    ///
    /// Search plugins widen a search by deriving extra requests from the
    /// original one (see ``derived(searchTerm:)``); every derived request
    /// keeps this `id`, so a result can always be traced back to the search
    /// that started it even though its `searchTerm` differs. `id` is
    /// deliberately excluded from `==`, which compares search content only.
    public let id: UUID

    /// How a request came to be: the caller's original, or one a search
    /// plugin derived from it. Lets a result be traced to its origin
    /// without inspecting its search term — see `Lyrics.isFromSearchPlugin`.
    public enum Origin: Equatable, Sendable {
        /// Built directly by the caller — the original search.
        case original
        /// Derived from the caller's request by a `LyricsSearchRequestPlugin`.
        case plugin
    }

    /// Whether this is the caller's original request or a plugin-derived one.
    public private(set) var origin: Origin = .original

    public var searchTerm: SearchTerm
    public var duration: TimeInterval
    public var limit: Int
    public var userInfo: [String: String]

    public enum SearchTerm: Equatable, Sendable {
        case keyword(String)
        case info(title: String, artist: String)
    }

    public init(searchTerm: SearchTerm, duration: TimeInterval, limit: Int = 6, userInfo: [String: String] = [:]) {
        self.id = UUID()
        self.searchTerm = searchTerm
        self.duration = duration
        self.limit = limit
        self.userInfo = userInfo
    }

    /// A copy of this request that shares its session `id` but searches a
    /// different term, with `origin` set to `.plugin`. Search plugins use
    /// this to add native-script or otherwise-corrected variants alongside
    /// the original search, so their results stay attributed to this session.
    public func derived(searchTerm: SearchTerm) -> LyricsSearchRequest {
        var derivedRequest = self
        derivedRequest.searchTerm = searchTerm
        derivedRequest.origin = .plugin
        return derivedRequest
    }

    /// Equality compares search *content* only. `id` is identity, not
    /// content: two requests with the same term, duration, limit and
    /// `userInfo` are equal regardless of which session each belongs to.
    public static func == (lhs: LyricsSearchRequest, rhs: LyricsSearchRequest) -> Bool {
        lhs.searchTerm == rhs.searchTerm
            && lhs.duration == rhs.duration
            && lhs.limit == rhs.limit
            && lhs.userInfo == rhs.userInfo
    }
}

extension LyricsSearchRequest.SearchTerm: CustomStringConvertible {
    public var description: String {
        switch self {
        case .keyword(let keyword):
            return keyword
        case .info(title: let title, artist: let artist):
            return title + " " + artist
        }
    }

    public var titleOnly: String {
        switch self {
        case .keyword(let string):
            return string
        case .info(let title, _):
            return title
        }
    }
}
