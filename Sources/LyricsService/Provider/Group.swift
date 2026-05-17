import Foundation
import LyricsCore
import FoundationToolbox

extension LyricsProviders {
    @Loggable
    public final class Group: LyricsProvider {
        public let providers: [LyricsProvider]

        public init(providers: [LyricsProvider] = []) {
            self.providers = providers
        }

        public func lyrics(for request: LyricsSearchRequest) -> AsyncThrowingStream<Lyrics, Error> {
            AsyncThrowingStream { continuation in
                let providers = self.providers
                let task = Task {
                    await withTaskGroup(of: Void.self) { group in
                        for provider in providers {
                            group.addTask {
                                do {
                                    for try await lyric in provider.lyrics(for: request) {
                                        continuation.yield(lyric)
                                    }
                                } catch {
                                    #log(.error, "A provider in the group failed: \(error)")
                                }
                            }
                        }
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    }
}
