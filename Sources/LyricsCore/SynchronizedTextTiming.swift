import Foundation

extension LyricsLine.Attachments {
    /// Exact character and time ranges recovered from a structured lyrics source.
    ///
    /// This attachment complements `InlineTimeTag`: the legacy attachment remains
    /// the compatibility path, while this model preserves word endings and nested
    /// syllable timings for renderers that understand them.
    public struct SynchronizedTextTiming: LyricsLineAttachment, Equatable, Hashable {
        public struct Syllable: Equatable, Hashable {
            public var characterRange: Range<Int>
            public var timeRange: Range<TimeInterval>

            public init(characterRange: Range<Int>, timeRange: Range<TimeInterval>) {
                self.characterRange = characterRange
                self.timeRange = timeRange
            }
        }

        public struct Word: Equatable, Hashable {
            public var characterRange: Range<Int>
            public var timeRange: Range<TimeInterval>
            public var syllables: [Syllable]

            public init(
                characterRange: Range<Int>,
                timeRange: Range<TimeInterval>,
                syllables: [Syllable] = []
            ) {
                self.characterRange = characterRange
                self.timeRange = timeRange
                self.syllables = syllables
            }
        }

        public var words: [Word]
        public var duration: TimeInterval?

        public init(words: [Word], duration: TimeInterval? = nil) {
            self.words = words
            self.duration = duration
        }

        /// Returns whether every range can be applied to a line with the supplied
        /// number of Swift `Character` values.
        public func isValid(forCharacterCount characterCount: Int) -> Bool {
            hasValidStructure(characterCount: characterCount)
        }

        public var description: String {
            guard let encodedTiming = EncodedTiming(self) else { return "" }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard let payloadData = try? encoder.encode(encodedTiming) else { return "" }
            return "\(Self.serializationVersion):\(payloadData.base64EncodedString())"
        }

        public init?(_ description: String) {
            let components = description.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard components.count == 2,
                  components[0] == Substring(Self.serializationVersion),
                  let payloadData = Data(base64Encoded: String(components[1])),
                  let encodedTiming = try? JSONDecoder().decode(EncodedTiming.self, from: payloadData),
                  let decodedTiming = encodedTiming.decodedTiming,
                  decodedTiming.hasValidStructure(characterCount: nil)
            else {
                return nil
            }
            self = decodedTiming
        }
    }
}

private extension LyricsLine.Attachments.SynchronizedTextTiming {
    static let serializationVersion = "1"

    func hasValidStructure(characterCount: Int?) -> Bool {
        guard !words.isEmpty,
              characterCount.map({ $0 >= 0 }) ?? true,
              duration.map({ $0.isFinite && $0 >= 0 }) ?? true
        else {
            return false
        }

        var precedingWordCharacterEnd = 0
        for word in words {
            guard word.characterRange.lowerBound >= precedingWordCharacterEnd,
                  word.characterRange.lowerBound >= 0,
                  word.characterRange.lowerBound < word.characterRange.upperBound,
                  characterCount.map({ word.characterRange.upperBound <= $0 }) ?? true,
                  word.timeRange.lowerBound.isFinite,
                  word.timeRange.upperBound.isFinite,
                  word.timeRange.lowerBound >= 0,
                  word.timeRange.lowerBound <= word.timeRange.upperBound
            else {
                return false
            }

            var precedingSyllableCharacterEnd = word.characterRange.lowerBound
            for syllable in word.syllables {
                guard syllable.characterRange.lowerBound >= precedingSyllableCharacterEnd,
                      syllable.characterRange.lowerBound >= word.characterRange.lowerBound,
                      syllable.characterRange.upperBound <= word.characterRange.upperBound,
                      syllable.characterRange.lowerBound < syllable.characterRange.upperBound,
                      syllable.timeRange.lowerBound.isFinite,
                      syllable.timeRange.upperBound.isFinite,
                      syllable.timeRange.lowerBound >= word.timeRange.lowerBound,
                      syllable.timeRange.upperBound <= word.timeRange.upperBound,
                      syllable.timeRange.lowerBound <= syllable.timeRange.upperBound
                else {
                    return false
                }
                precedingSyllableCharacterEnd = syllable.characterRange.upperBound
            }

            precedingWordCharacterEnd = word.characterRange.upperBound
        }
        return true
    }

    struct EncodedTiming: Codable {
        struct EncodedWord: Codable {
            struct EncodedSyllable: Codable {
                let startingCharacterIndex: Int
                let endingCharacterIndex: Int
                let startingTimeMilliseconds: Int
                let endingTimeMilliseconds: Int

                init?(_ syllable: Syllable) {
                    guard let startingTimeMilliseconds = Self.milliseconds(from: syllable.timeRange.lowerBound),
                          let endingTimeMilliseconds = Self.milliseconds(from: syllable.timeRange.upperBound)
                    else {
                        return nil
                    }
                    self.startingCharacterIndex = syllable.characterRange.lowerBound
                    self.endingCharacterIndex = syllable.characterRange.upperBound
                    self.startingTimeMilliseconds = startingTimeMilliseconds
                    self.endingTimeMilliseconds = endingTimeMilliseconds
                }

                var decodedSyllable: Syllable? {
                    guard startingCharacterIndex >= 0,
                          startingCharacterIndex < endingCharacterIndex,
                          startingTimeMilliseconds >= 0,
                          startingTimeMilliseconds <= endingTimeMilliseconds
                    else {
                        return nil
                    }
                    return Syllable(
                        characterRange: startingCharacterIndex ..< endingCharacterIndex,
                        timeRange: Self.seconds(from: startingTimeMilliseconds) ..< Self.seconds(from: endingTimeMilliseconds)
                    )
                }

                private static func milliseconds(from time: TimeInterval) -> Int? {
                    guard time.isFinite else { return nil }
                    return Int(exactly: (time * 1000).rounded())
                }

                private static func seconds(from milliseconds: Int) -> TimeInterval {
                    TimeInterval(milliseconds) / 1000
                }
            }

            let startingCharacterIndex: Int
            let endingCharacterIndex: Int
            let startingTimeMilliseconds: Int
            let endingTimeMilliseconds: Int
            let syllables: [EncodedSyllable]

            init?(_ word: Word) {
                guard let startingTimeMilliseconds = Self.milliseconds(from: word.timeRange.lowerBound),
                      let endingTimeMilliseconds = Self.milliseconds(from: word.timeRange.upperBound)
                else {
                    return nil
                }
                let encodedSyllables = word.syllables.compactMap(EncodedSyllable.init)
                guard encodedSyllables.count == word.syllables.count else { return nil }
                self.startingCharacterIndex = word.characterRange.lowerBound
                self.endingCharacterIndex = word.characterRange.upperBound
                self.startingTimeMilliseconds = startingTimeMilliseconds
                self.endingTimeMilliseconds = endingTimeMilliseconds
                self.syllables = encodedSyllables
            }

            var decodedWord: Word? {
                guard startingCharacterIndex >= 0,
                      startingCharacterIndex < endingCharacterIndex,
                      startingTimeMilliseconds >= 0,
                      startingTimeMilliseconds <= endingTimeMilliseconds
                else {
                    return nil
                }
                let decodedSyllables = syllables.compactMap(\.decodedSyllable)
                guard decodedSyllables.count == syllables.count else { return nil }
                return Word(
                    characterRange: startingCharacterIndex ..< endingCharacterIndex,
                    timeRange: Self.seconds(from: startingTimeMilliseconds) ..< Self.seconds(from: endingTimeMilliseconds),
                    syllables: decodedSyllables
                )
            }

            private static func milliseconds(from time: TimeInterval) -> Int? {
                guard time.isFinite else { return nil }
                return Int(exactly: (time * 1000).rounded())
            }

            private static func seconds(from milliseconds: Int) -> TimeInterval {
                TimeInterval(milliseconds) / 1000
            }
        }

        let durationMilliseconds: Int?
        let words: [EncodedWord]

        init?(_ timing: LyricsLine.Attachments.SynchronizedTextTiming) {
            guard timing.hasValidStructure(characterCount: nil) else { return nil }
            let encodedWords = timing.words.compactMap(EncodedWord.init)
            guard encodedWords.count == timing.words.count else { return nil }
            if let duration = timing.duration {
                guard duration.isFinite,
                      let durationMilliseconds = Int(exactly: (duration * 1000).rounded())
                else {
                    return nil
                }
                self.durationMilliseconds = durationMilliseconds
            } else {
                self.durationMilliseconds = nil
            }
            self.words = encodedWords
        }

        var decodedTiming: LyricsLine.Attachments.SynchronizedTextTiming? {
            guard durationMilliseconds.map({ $0 >= 0 }) ?? true else { return nil }
            let decodedWords = words.compactMap(\.decodedWord)
            guard decodedWords.count == words.count else { return nil }
            let decodedDuration = durationMilliseconds.map { TimeInterval($0) / 1000 }
            return LyricsLine.Attachments.SynchronizedTextTiming(
                words: decodedWords,
                duration: decodedDuration
            )
        }
    }
}
