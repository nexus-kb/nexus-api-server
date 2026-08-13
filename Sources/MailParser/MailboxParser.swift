//
//  MailboxParser.swift
//  MailParser
//
//  Created by Tanuj Ravi Rao on 8/13/26.
//

import Foundation

public struct RFCMailboxParser: Sendable {
    public init() {}

    public func parseList(
        _ rawValue: String?
    ) -> [Mailbox] {
        MailboxParser.parseList(rawValue)
    }
}

enum MailboxParser {
    static func parseList(
        _ rawValue: String?
    ) -> [Mailbox] {
        guard let rawValue else {
            return []
        }

        return splitAddresses(rawValue).compactMap(
            parseMailbox
        )
    }

    private static func parseMailbox(
        _ rawValue: String
    ) -> Mailbox? {
        var value = rawValue
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .trimmingCharacters(
                in: CharacterSet(charactersIn: ";")
            )

        if let groupColon = firstUnquotedCharacter(
            ":",
            in: value
        ) {
            value = String(
                value[value.index(after: groupColon)...]
            ).trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        }

        guard !value.isEmpty else {
            return nil
        }

        let name: String?
        let address: String

        if let open = firstUnquotedCharacter(
            "<",
            in: value
        ),
           let close = value[open...].firstIndex(
               of: ">"
           )
        {
            name = cleanDisplayName(
                String(value[..<open])
            )

            address = String(
                value[value.index(after: open)..<close]
            ).trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        } else {
            let components = value.split(
                whereSeparator: \.isWhitespace
            )

            guard let addressComponent =
                    components.last(where: {
                        $0.contains("@")
                    })
            else {
                return nil
            }

            address = String(addressComponent)
                .trimmingCharacters(
                    in: CharacterSet(
                        charactersIn: "<>()[],;\""
                    )
                )

            if let commentStart = value.lastIndex(of: "("),
               let commentEnd = value.lastIndex(of: ")"),
               commentStart < commentEnd
            {
                name = cleanDisplayName(
                    String(
                        value[
                            value.index(
                                after: commentStart
                            )..<commentEnd
                        ]
                    )
                )
            } else {
                name = nil
            }
        }

        guard address.contains("@") else {
            return nil
        }

        return Mailbox(
            name: name,
            address: address
        )
    }

    private static func cleanDisplayName(
        _ rawValue: String
    ) -> String? {
        var value = rawValue
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        while value.first == "\"",
              value.last == "\"",
              value.count >= 2
        {
            value.removeFirst()
            value.removeLast()
        }

        value = value
            .replacingOccurrences(
                of: "\\\"",
                with: "\""
            )
            .replacingOccurrences(
                of: "\\\\",
                with: "\\"
            )

        value = HeaderValueDecoder.decodeEncodedWords(
            value
        ).trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return value.isEmpty ? nil : value
    }

    private static func splitAddresses(
        _ rawValue: String
    ) -> [String] {
        var addresses: [String] = []
        var current = ""
        var isQuoted = false
        var isEscaped = false
        var angleDepth = 0
        var commentDepth = 0

        for character in rawValue {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }

            if character == "\\", isQuoted {
                current.append(character)
                isEscaped = true
                continue
            }

            if character == "\"", commentDepth == 0 {
                isQuoted.toggle()
                current.append(character)
                continue
            }

            if !isQuoted {
                if character == "<" {
                    angleDepth += 1
                } else if character == ">" {
                    angleDepth = max(
                        0,
                        angleDepth - 1
                    )
                } else if character == "(" {
                    commentDepth += 1
                } else if character == ")" {
                    commentDepth = max(
                        0,
                        commentDepth - 1
                    )
                }
            }

            if character == ",",
               !isQuoted,
               angleDepth == 0,
               commentDepth == 0
            {
                addresses.append(current)
                current = ""
                continue
            }

            current.append(character)
        }

        if !current.isEmpty {
            addresses.append(current)
        }

        return addresses
    }

    private static func firstUnquotedCharacter(
        _ target: Character,
        in value: String
    ) -> String.Index? {
        var isQuoted = false
        var isEscaped = false

        for index in value.indices {
            let character = value[index]

            if isEscaped {
                isEscaped = false
                continue
            }

            if character == "\\", isQuoted {
                isEscaped = true
                continue
            }

            if character == "\"" {
                isQuoted.toggle()
                continue
            }

            if character == target, !isQuoted {
                return index
            }
        }

        return nil
    }
}
