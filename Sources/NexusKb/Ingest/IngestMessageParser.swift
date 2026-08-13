//
//  IngestMessageParser.swift
//  NexusKb
//
//  Created by Tanuj Ravi Rao on 8/13/26.
//

import Foundation
import MailParser

struct ParsedIngestMessage: Sendable, Equatable {
    let message: MailMessage
    let author: Mailbox
    let patch: ParsedPatchMetadata

    var authorDisplayString: String {
        author.displayString
    }

    var toDisplayString: String {
        message.to
            .map(\.displayString)
            .joined(separator: ", ")
    }

    var ccDisplayString: String {
        message.cc
            .map(\.displayString)
            .joined(separator: ", ")
    }
}

struct ParsedPatchMetadata: Sendable, Equatable {
    static let parserVersion: Int32 = 2

    let partIndex: Int32
    let totalParts: Int32
    let version: Int32?
    let isPatchOrCover: Bool
    let diff: String?
}

struct IngestMessageParser: Sendable {
    private let messageParser = RFCMessageParser()
    private let mailboxParser = RFCMailboxParser()

    func parse(
        _ data: Data
    ) throws -> ParsedIngestMessage {
        let message = try messageParser.parse(data)

        return ParsedIngestMessage(
            message: message,
            author: resolvedAuthor(for: message),
            patch: PatchSubjectParser.parse(
                subject: message.subject,
                body: message.textBody
            )
        )
    }

    private func resolvedAuthor(
        for message: MailMessage
    ) -> Mailbox {
        let sender = message.from ?? Mailbox(
            name: nil,
            address: "unknown@localhost"
        )

        guard let originalValue = message.headers.firstValue(
            named: "X-Original-From"
        ),
        let original = mailboxParser
            .parseList(originalValue)
            .first
        else {
            return sender
        }

        return B4Alias.matches(
            alias: sender.address,
            real: original.address
        ) ? original : sender
    }
    
    private enum B4Alias {
        static func matches(
            alias: String,
            real: String
        ) -> Bool {
            let alias = alias.lowercased()

            guard alias.hasPrefix("devnull+"),
                  let atIndex = alias.lastIndex(of: "@"),
                  atIndex > alias.index(
                      alias.startIndex,
                      offsetBy: 8
                  )
            else {
                return false
            }

            let encodedAddress = alias[
                alias.index(
                    alias.startIndex,
                    offsetBy: 8
                )..<atIndex
            ]
            let domain = alias[
                alias.index(after: atIndex)...
            ]

            guard domain == "kernel.org"
                    || domain == "linux.dev"
            else {
                return false
            }

            let realAddress = real
                .lowercased()
                .replacingOccurrences(
                    of: "@",
                    with: "."
                )

            return encodedAddress == realAddress
        }
    }
}

private enum PatchSubjectParser {
    static func parse(
        subject: String,
        body: String
    ) -> ParsedPatchMetadata {
        let (index, total) = partPosition(
            in: subject
        )
        let version = version(in: subject)
        let lowerSubject = subject.lowercased()
        let trimmedSubject = lowerSubject
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        
        let hasDiff = body.contains("diff --git")
        || (
            body.contains("--- ")
            && body.contains("+++ ")
            && body.contains("@@ -")
        )
        
        let isSeries = total > 1 || index == 0
        let isPatchOrCover =
        !isReply(
            trimmedSubject,
            lowerSubject: lowerSubject
        )
        && (
            trimmedSubject.contains("patch")
            || trimmedSubject.contains("rfc")
            || hasDiff
            || isSeries
        )
        
        return ParsedPatchMetadata(
            partIndex: index,
            totalParts: max(1, total),
            version: version,
            isPatchOrCover: isPatchOrCover,
            diff: hasDiff && index != 0
            ? body
            : nil
        )
    }
    
    private static func isReply(
        _ subject: String,
        lowerSubject: String
    ) -> Bool {
        let prefixes = [
            "re:",
            "fwd:",
            "forwarded:",
            "aw:",
            "wg:",
            "回复:",
            "回复：",
            "答复:",
            "答复：",
            "[reproducer]",
        ]

        return prefixes.contains(
            where: subject.hasPrefix
        )
        || lowerSubject.contains("(was ")
        || lowerSubject.contains("(was:")
    }
    
    private static func partPosition(
        in subject: String
    ) -> (Int32, Int32) {
        let patterns = [
            #"(?i)\[.*?\b(?:PATCH|RFC|RESEND|v\d+)\b.*?(\d+)/(\d+).*?\]"#,
            #"(?i)\b(?:PATCH|RFC|RESEND)\s+(\d+)/(\d+)\b"#,
        ]

        for pattern in patterns {
            if let values = firstIntegerCaptures(
                pattern: pattern,
                in: subject,
                count: 2
            ) {
                return (values[0], values[1])
            }
        }

        let cleaned = subject.replacingOccurrences(
            of: #"\[.*?\]"#,
            with: "",
            options: .regularExpression
        )

        if let values = firstIntegerCaptures(
            pattern: #"^\s*(\d+)/(\d+)\b"#,
            in: cleaned,
            count: 2
        ) {
            return (values[0], values[1])
        }

        return (1, 1)
    }
    
    private static func version(
        in subject: String
    ) -> Int32? {
        let pattern =
            #"(?i)(?:\[[^\]]*?\bv(\d+)\b[^\]]*?\]|^\s*v(\d+)\b|PATCH\W*v(\d+)\b)"#

        guard let expression = try? NSRegularExpression(
            pattern: pattern
        ) else {
            return nil
        }

        let source = subject as NSString

        guard let match = expression.firstMatch(
            in: subject,
            range: NSRange(
                location: 0,
                length: source.length
            )
        ) else {
            return nil
        }

        for index in 1..<match.numberOfRanges {
            let range = match.range(at: index)

            if range.location != NSNotFound {
                return Int32(
                    source.substring(with: range)
                )
            }
        }

        return nil
    }
    
    private static func firstIntegerCaptures(
        pattern: String,
        in value: String,
        count: Int
    ) -> [Int32]? {
        guard let expression = try? NSRegularExpression(
            pattern: pattern
        ) else {
            return nil
        }

        let source = value as NSString

        guard let match = expression.firstMatch(
            in: value,
            range: NSRange(
                location: 0,
                length: source.length
            )
        ),
        match.numberOfRanges > count
        else {
            return nil
        }

        let values = (1...count).compactMap {
            capture -> Int32? in

            let range = match.range(at: capture)

            guard range.location != NSNotFound else {
                return nil
            }

            return Int32(
                source.substring(with: range)
            )
        }

        return values.count == count
            ? values
            : nil
    }
}
