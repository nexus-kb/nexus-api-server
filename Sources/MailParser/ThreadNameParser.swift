/*
 * SPDX-FileCopyrightText: 2020 Stalwart Labs LLC <hello@stalw.art>
 *
 * SPDX-License-Identifier: Apache-2.0 OR MIT
 */

/// Utilities for deriving the RFC-style base subject used to group messages.
public enum ThreadNameParser: Sendable {
    /// Removes localized reply/forward prefixes, leading list tags, and trailing
    /// forward markers. The behavior follows `mail-parser`'s `thread_name`.
    public static func threadName(_ text: String) -> String {
        var tokenStart = text.startIndex
        var tokenEnd: String.Index?

        var threadNameStart = text.startIndex
        var forwardStart: String.Index?
        var forwardEnd: String.Index?
        var lastBlobEnd = text.startIndex

        var inBlob = false
        var ignoreBlob = false
        var sawHeader = false
        var sawBlobHeader = false
        var foundToken = false

        for index in text.indices {
            let character = text[index]

            switch character {
            case "[":
                guard !inBlob else {
                    return finish(
                        text,
                        threadNameStart: threadNameStart,
                        lastBlobEnd: lastBlobEnd,
                        forwardStart: forwardStart,
                        forwardEnd: forwardEnd
                    )
                }

                if foundToken {
                    let end = tokenEnd ?? index
                    let prefix = String(text[tokenStart..<end]).lowercased()
                    guard isReplyPrefix(prefix) || isForwardPrefix(prefix) else {
                        return finish(
                            text,
                            threadNameStart: threadNameStart,
                            lastBlobEnd: lastBlobEnd,
                            forwardStart: forwardStart,
                            forwardEnd: forwardEnd
                        )
                    }
                    sawHeader = true
                }
                foundToken = false
                inBlob = true

            case "]" where inBlob:
                if sawBlobHeader && foundToken {
                    forwardStart = tokenStart
                    forwardEnd = index
                }
                if !sawHeader {
                    lastBlobEnd = text.index(after: index)
                }
                inBlob = false
                foundToken = false
                sawBlobHeader = false
                ignoreBlob = false

            case ":" where !inBlob:
                if (sawHeader && foundToken) || (!sawHeader && !foundToken) {
                    return finish(
                        text,
                        threadNameStart: threadNameStart,
                        lastBlobEnd: lastBlobEnd,
                        forwardStart: forwardStart,
                        forwardEnd: forwardEnd
                    )
                }

                if !sawHeader {
                    let end = tokenEnd ?? index
                    let prefix = String(text[tokenStart..<end]).lowercased()
                    guard isReplyPrefix(prefix) || isForwardPrefix(prefix) else {
                        return finish(
                            text,
                            threadNameStart: threadNameStart,
                            lastBlobEnd: lastBlobEnd,
                            forwardStart: forwardStart,
                            forwardEnd: forwardEnd
                        )
                    }
                } else {
                    sawHeader = false
                }

                threadNameStart = text.index(after: index)
                foundToken = false

            case ":" where inBlob && !ignoreBlob:
                let end = tokenEnd ?? index
                let prefix = String(text[tokenStart..<end]).lowercased()
                if isForwardPrefix(prefix) {
                    foundToken = false
                    sawBlobHeader = true
                } else if sawBlobHeader && isReplyPrefix(prefix) {
                    foundToken = false
                } else {
                    ignoreBlob = true
                }

            case _ where character.isWhitespace:
                if tokenEnd == nil {
                    tokenEnd = index
                }

            default:
                if !foundToken {
                    tokenStart = index
                    tokenEnd = nil
                    foundToken = true
                } else if !inBlob,
                          text[tokenStart..<index].utf8.count > 21 {
                    return finish(
                        text,
                        threadNameStart: threadNameStart,
                        lastBlobEnd: lastBlobEnd,
                        forwardStart: forwardStart,
                        forwardEnd: forwardEnd
                    )
                }
            }
        }

        return finish(
            text,
            threadNameStart: threadNameStart,
            lastBlobEnd: lastBlobEnd,
            forwardStart: forwardStart,
            forwardEnd: forwardEnd
        )
    }

    /// Alias matching the terminology used by RFC 5256.
    public static func baseSubject(_ text: String) -> String {
        threadName(text)
    }

    private static func finish(
        _ text: String,
        threadNameStart: String.Index,
        lastBlobEnd: String.Index,
        forwardStart: String.Index?,
        forwardEnd: String.Index?
    ) -> String {
        if lastBlobEnd > threadNameStart
            || (forwardStart.map {
                lastBlobEnd > $0 && $0 > threadNameStart
            } ?? false)
        {
            let result = trimTrailingForward(String(text[lastBlobEnd...]))
            if !result.isEmpty {
                return result
            }
        }

        if let forwardStart,
           let forwardEnd,
           threadNameStart < forwardStart
        {
            let result = trimTrailingForward(
                String(text[forwardStart..<forwardEnd])
            )
            if !result.isEmpty {
                return result
            }
        }

        return trimTrailingForward(String(text[threadNameStart...]))
    }

    private static func trimTrailingForward(_ text: String) -> String {
        var inParentheses = false
        var trimEnd = true
        var endFound = false

        var textStart = text.startIndex
        var textEnd = text.endIndex
        var forwardEnd = text.startIndex

        for index in text.indices.reversed() {
            let character = text[index]

            switch character {
            case "(" where !endFound:
                if inParentheses {
                    inParentheses = false
                    let prefixStart = text.index(after: index)
                    if prefixStart < forwardEnd,
                       text.distance(from: index, to: forwardEnd) > 2,
                       isForwardPrefix(
                           String(text[prefixStart..<forwardEnd]).lowercased()
                       )
                    {
                        textEnd = index
                        trimEnd = true
                        continue
                    }
                }
                endFound = true

            case ")" where !endFound:
                if !inParentheses {
                    inParentheses = true
                    forwardEnd = index
                } else {
                    endFound = true
                }

            case _ where character.isWhitespace:
                if trimEnd {
                    textEnd = index
                }
                continue

            default:
                if !inParentheses && !endFound {
                    endFound = true
                }
            }

            if trimEnd {
                trimEnd = false
            }
            textStart = index
        }

        guard textEnd >= textStart else {
            return ""
        }
        return String(text[textStart..<textEnd])
    }

    private static func isReplyPrefix(_ prefix: String) -> Bool {
        replyPrefixes.contains(prefix)
    }

    private static func isForwardPrefix(_ prefix: String) -> Bool {
        forwardPrefixes.contains(prefix)
    }

    private static let replyPrefixes: Set<String> = [
        "re", "res", "sv", "antw", "ref", "aw", "απ", "השב", "vá", "r",
        "rif", "bls", "odp", "ynt", "atb", "رد", "回复", "转发",
    ]

    private static let forwardPrefixes: Set<String> = [
        "fwd", "fw", "rv", "enc", "vs", "doorst", "vl", "tr", "wg", "πρθ",
        "הועבר", "továbbítás", "i", "fs", "trs", "vb", "pd", "i̇lt", "yml",
        "إعادة توجيه", "回覆", "轉寄",
    ]
}
