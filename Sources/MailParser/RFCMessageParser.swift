//
//  RFCMessageParser.swift
//  MailParser
//
//  Created by Tanuj Ravi Rao on 8/13/26.
//

import Foundation

public struct RFCMessageParser: Sendable {
    private let dateParser: MailDateParser

    public init() {
        dateParser = MailDateParser()
    }

    public func parse(
        _ data: Data
    ) throws -> MailMessage {
        let entity = try MessageSyntax.parseEntity(data)

        guard let rawMessageID = entity.headers.firstValue(
            named: "Message-ID"
        ),
        let messageID = MessageIDParser.firstID(
            in: rawMessageID
        ) else {
            throw MailParserError.missingMessageID
        }

        let subject = HeaderValueDecoder.decodeEncodedWords(
            entity.headers.firstValue(
                named: "Subject"
            ) ?? "(no subject)"
        )

        let textBodies =
            try MIMEBodyDecoder.decodeTextBodies(
                from: entity
            )

        return MailMessage(
            headers: entity.headers,
            messageID: messageID,
            subject: subject,
            from: MailboxParser.parseList(
                entity.headers.firstValue(named: "From")
            ).first,
            to: entity.headers.values(named: "To")
                .flatMap(MailboxParser.parseList),
            cc: entity.headers.values(named: "Cc")
                .flatMap(MailboxParser.parseList),
            date: dateParser.parse(
                entity.headers.firstValue(named: "Date")
            ),
            receivedDate: dateParser.parseReceived(
                entity.headers.firstValue(named: "Received")
            ),
            inReplyTo: entity.headers
                .firstValue(named: "In-Reply-To")
                .flatMap(MessageIDParser.firstID),
            references: entity.headers
                .values(named: "References")
                .flatMap(MessageIDParser.allIDs),
            textBody: textBodies.joined(separator: "\n")
        )
    }
}

enum MessageIDParser {
    private static let bracketedIDExpression =
        try! NSRegularExpression(
            pattern: #"<([^<>\s]+)>"#
        )

    static func firstID(
        in value: String
    ) -> String? {
        allIDs(in: value).first
    }

    static func allIDs(
        in value: String
    ) -> [String] {
        let source = value as NSString
        let matches = bracketedIDExpression.matches(
            in: value,
            range: NSRange(
                location: 0,
                length: source.length
            )
        )

        if !matches.isEmpty {
            return matches.map {
                source.substring(
                    with: $0.range(at: 1)
                )
            }
        }

        let fallback = value
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .trimmingCharacters(
                in: CharacterSet(charactersIn: "<>")
            )

        guard !fallback.isEmpty,
              !fallback.contains(where: \.isWhitespace)
        else {
            return []
        }

        return [fallback]
    }
}

struct MailDateParser: Sendable {
    private static let formats = [
        "EEE, d MMM yy HH:mm:ss Z",
        "d MMM yy HH:mm:ss Z",
        "EEE, d MMM yyyy HH:mm:ss Z",
        "EEE, d MMM yyyy HH:mm Z",
        "d MMM yyyy HH:mm:ss Z",
        "d MMM yyyy HH:mm Z",
        "EEE, d MMM yyyy HH:mm:ss z",
        "d MMM yyyy HH:mm:ss z",
    ]

    private let formatters: [DateFormatter]

    init() {
        formatters = Self.formats.map { format in
            let formatter = DateFormatter()

            formatter.locale = Locale(
                identifier: "en_US_POSIX"
            )
            formatter.calendar = Calendar(
                identifier: .gregorian
            )
            formatter.timeZone = TimeZone(
                secondsFromGMT: 0
            )
            formatter.dateFormat = format
            formatter.isLenient = true

            return formatter
        }
    }

    func parse(
        _ rawValue: String?
    ) -> Date? {
        guard let rawValue else {
            return nil
        }

        let value = Self.removingComments(
            from: rawValue
        ).trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        for formatter in formatters {
            if let date = formatter.date(
                from: value
            ) {
                return date
            }
        }

        return nil
    }

    func parseReceived(
        _ rawValue: String?
    ) -> Date? {
        guard let rawValue,
            let semicolon = rawValue.lastIndex(
                of: ";"
            )
        else {
            return nil
        }

        return parse(
            String(
                rawValue[
                    rawValue.index(
                        after: semicolon
                    )...
                ]
            )
        )
    }

    private static func removingComments(
        from value: String
    ) -> String {
        var output = ""
        var commentDepth = 0
        var isEscaped = false

        for character in value {
            if isEscaped {
                if commentDepth == 0 {
                    output.append(character)
                }

                isEscaped = false
                continue
            }

            if character == "\\" {
                if commentDepth == 0 {
                    output.append(character)
                }

                isEscaped = true
                continue
            }

            if character == "(" {
                commentDepth += 1
                continue
            }

            if character == ")",
                commentDepth > 0
            {
                commentDepth -= 1
                continue
            }

            if commentDepth == 0 {
                output.append(character)
            }
        }

        return output
    }
}
