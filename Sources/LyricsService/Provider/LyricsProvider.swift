import Foundation
import LyricsCore
import FoundationToolbox

public enum LyricsProviders {}

public protocol LyricsProvider: Sendable {
    func lyrics(for request: LyricsSearchRequest) -> AsyncThrowingStream<Lyrics, Error>
}

protocol _LyricsProvider: LyricsProvider {
    associatedtype LyricsToken

    static var service: String { get }

    func search(for request: LyricsSearchRequest) async throws -> [LyricsToken]

    func fetch(with token: LyricsToken) async throws -> Lyrics
}

@Loggable
private enum LyricsProviderLog {
    static func fetchTaskFailed(_ error: any Error) {
        #log(.error, "A fetch task failed, skipping. Error: \(error)")
    }
}

extension _LyricsProvider {
    func lyrics(for request: LyricsSearchRequest) -> AsyncThrowingStream<Lyrics, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let tokens = try await self.search(for: request)
                    let limitedTokens = tokens.prefix(request.limit)

                    let fetchTasks: [Task<Lyrics, Error>] = limitedTokens.map { token in
                        Task {
                            let lrc = try await self.fetch(with: token)
                            lrc.metadata.request = request
                            lrc.metadata.service = Self.service
                            return lrc
                        }
                    }

                    for task in fetchTasks {
                        do {
                            let lyric = try await task.value
                            continuation.yield(lyric)
                        } catch {
                            LyricsProviderLog.fetchTaskFailed(error)
                        }
                    }

                    continuation.finish()

                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
