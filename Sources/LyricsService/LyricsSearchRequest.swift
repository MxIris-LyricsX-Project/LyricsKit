import Foundation

public struct LyricsSearchRequest: Equatable, Sendable {
    public var searchTerm: SearchTerm
    public var duration: TimeInterval
    public var limit: Int
    public var userInfo: [String: String]

    public enum SearchTerm: Equatable, Sendable {
        case keyword(String)
        case info(title: String, artist: String)
    }

    public init(searchTerm: SearchTerm, duration: TimeInterval, limit: Int = 6, userInfo: [String: String] = [:]) {
        self.searchTerm = searchTerm
        self.duration = duration
        self.limit = limit
        self.userInfo = userInfo
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
