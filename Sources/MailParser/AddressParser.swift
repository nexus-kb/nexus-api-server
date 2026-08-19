/*
 * SPDX-FileCopyrightText: 2020 Stalwart Labs LLC <hello@stalw.art>
 *
 * SPDX-License-Identifier: Apache-2.0 OR MIT
 */

import Foundation

/// Parses RFC 5322 mailbox lists and groups. The parser intentionally accepts
/// obsolete and commonly malformed forms in the same best-effort manner as
/// Stalwart's `mail-parser`.
public struct AddressParser: Sendable {
    public init() {}

    public func parse(_ value: String) -> Address? {
        var parser = Parser(input: Self.headerValue(value))
        return parser.parse()
    }

    public func parse<C: Collection>(_ bytes: C) -> Address?
    where C.Element == UInt8 {
        parse(RFC2047Decoder.structurallyOpaqueWords(bytes))
    }

    public static func parse(_ value: String) -> Address? {
        AddressParser().parse(value)
    }

    /// Parses a standalone address field, returning an empty list for an empty
    /// or unusable field value.
    public func parseList(_ value: String) -> Address {
        parse(value) ?? .list([])
    }

    /// Returns the ASCII local part before the first `@`.
    public static func localPart(of address: String) -> Substring? {
        guard let at = address.firstIndex(of: "@"),
              at != address.startIndex,
              address.index(after: at) != address.endIndex,
              address[..<at].utf8.allSatisfy({ $0 < 0x80 })
        else {
            return nil
        }
        return address[..<at]
    }

    /// Returns the domain after an ASCII local part and the first `@`.
    public static func domain(of address: String) -> Substring? {
        guard let at = address.firstIndex(of: "@"),
              at != address.startIndex,
              address[..<at].utf8.allSatisfy({ $0 < 0x80 })
        else {
            return nil
        }
        let start = address.index(after: at)
        return start == address.endIndex ? nil : address[start...]
    }

    /// Returns the local part with a plus-addressing detail removed.
    public static func userPart(of address: String) -> Substring? {
        guard let at = address.firstIndex(of: "@"),
              at != address.startIndex,
              address.index(after: at) != address.endIndex
        else {
            return nil
        }

        let local = address[..<at]
        if let plus = local.firstIndex(of: "+") {
            guard plus != local.startIndex,
                  local[..<plus].utf8.allSatisfy({ $0 < 0x80 })
            else {
                return nil
            }
            return local[..<plus]
        }

        return local.utf8.allSatisfy({ $0 < 0x80 })
            ? local
            : nil
    }

    /// Returns the text after the final plus in an ASCII local part.
    public static func detailPart(of address: String) -> Substring? {
        guard let at = address.firstIndex(of: "@"),
              at != address.startIndex,
              address.index(after: at) != address.endIndex
        else {
            return nil
        }

        let local = address[..<at]
        guard local.utf8.allSatisfy({ $0 < 0x80 }),
              let plus = local.lastIndex(of: "+")
        else {
            return nil
        }

        let start = local.index(after: plus)
        return local[start...]
    }

    fileprivate static func headerValue(_ source: String) -> String {
        let source = source.replacingOccurrences(of: "\r\n", with: "\n")
        var output = ""
        var index = source.startIndex

        while index < source.endIndex {
            let character = source[index]
            if character == "\r" || character == "\n" {
                var next = source.index(after: index)
                guard next < source.endIndex,
                      source[next] == " " || source[next] == "\t"
                else {
                    break
                }

                while next < source.endIndex,
                      source[next] == " " || source[next] == "\t"
                {
                    next = source.index(after: next)
                }
                if output.last != "\\", output.last != " " {
                    output.append("\u{1F}")
                }
                index = next
                continue
            }

            output.append(character)
            index = source.index(after: index)
        }

        return output
    }
}

private extension AddressParser {
    enum State: Equatable {
        case address
        case name
        case quote
        case comment
    }

    struct Parser {
        let input: String
        var state: State = .name
        var states: [State] = []
        var escaped = false
        var token = ""
        var tokenContainsAt = false

        var nameTokens: [String] = []
        var mailTokens: [String] = []
        var commentTokens: [String] = []

        var addresses: [MailAddress] = []
        var groupName: String?
        var groupComment: String?
        var groups: [AddressGroup] = []

        mutating func parse() -> Address? {
            var index = input.startIndex
            while index < input.endIndex {
                let character = input[index]

                if escaped {
                    token.append(character)
                    escaped = false
                    index = input.index(after: index)
                    continue
                }

                switch character {
                case "\\" where state != .name:
                    escaped = true

                case "," where state == .name:
                    addToken()
                    addAddress()

                case "<" where state == .name:
                    // Once an angle address starts, a preceding addr-spec-shaped
                    // token is a display name (an obsolete but common form).
                    tokenContainsAt = false
                    addToken()
                    states.append(.name)
                    state = .address

                case ">" where state == .address:
                    addToken()
                    state = states.popLast() ?? .name

                case "\"" where state == .name:
                    addToken()
                    states.append(.name)
                    state = .quote

                case "\"" where state == .quote:
                    addToken(preserveOuterWhitespace: true)
                    state = states.popLast() ?? .name

                case "@" where state == .name:
                    tokenContainsAt = true
                    token.append(character)

                case "(" where state != .quote:
                    if state == .comment {
                        token.append(character)
                    } else {
                        addToken()
                    }
                    states.append(state)
                    state = .comment

                case ")" where state == .comment:
                    let previous = states.popLast() ?? .name
                    if previous == .comment {
                        token.append(character)
                    } else {
                        addToken()
                        state = previous
                    }

                case ":" where state == .name:
                    addGroup()
                    addToken()
                    addGroupDetails()

                case ";" where state == .name:
                    addToken()
                    addAddress()
                    addGroup()

                case "\u{1F}" where state == .address:
                    break

                case "\u{1F}":
                    token.append(" ")

                default:
                    token.append(character)
                }

                index = input.index(after: index)
            }

            addToken(preserveOuterWhitespace: state == .quote)
            addAddress()

            if groupName != nil || !groups.isEmpty {
                addGroup()
                return groups.isEmpty ? nil : .group(groups)
            }
            return addresses.isEmpty ? nil : .list(addresses)
        }

        mutating func addToken(preserveOuterWhitespace: Bool = false) {
            let raw = preserveOuterWhitespace
                ? token
                : token.trimmingCharacters(in: .whitespacesAndNewlines)
            defer {
                token = ""
                tokenContainsAt = false
            }
            guard !raw.isEmpty else {
                return
            }

            switch state {
            case .address:
                mailTokens.append(raw)
            case .name where tokenContainsAt:
                mailTokens.append(raw)
            case .name:
                nameTokens.append(raw)
            case .quote:
                nameTokens.append(raw)
            case .comment:
                commentTokens.append(raw)
            }
        }

        mutating func addAddress() {
            let rawName = joined(nameTokens)
            let rawMail = mailTokens.joined()
            let rawComment = joined(commentTokens)

            nameTokens.removeAll(keepingCapacity: true)
            mailTokens.removeAll(keepingCapacity: true)
            commentTokens.removeAll(keepingCapacity: true)

            let name = rawName.map(RFC2047Decoder.decodeWords)
            let mail = rawMail.isEmpty ? nil : rawMail
            let comment = rawComment.map(RFC2047Decoder.decodeWords)

            switch (name, mail, comment) {
            case let (.some(name), .some(mail), .some(comment)):
                addresses.append(
                    MailAddress(name: "\(name) (\(comment))", address: mail)
                )
            case let (.some(name), .some(mail), .none):
                addresses.append(MailAddress(name: name, address: mail))
            case let (.none, .some(mail), .some(comment)):
                addresses.append(MailAddress(name: comment, address: mail))
            case let (.none, .some(mail), .none):
                addresses.append(MailAddress(name: nil, address: mail))
            case let (.some(name), .none, .some(comment)):
                if !name.contains(where: \.isWhitespace) {
                    addresses.append(MailAddress(name: comment, address: name))
                } else {
                    addresses.append(
                        MailAddress(name: "\(name) (\(comment))", address: nil)
                    )
                }
            case let (.some(name), .none, .none):
                addresses.append(MailAddress(name: name, address: nil))
            case let (.none, .none, .some(comment)):
                addresses.append(MailAddress(name: comment, address: nil))
            case (.none, .none, .none):
                break
            }
        }

        mutating func addGroupDetails() {
            if let name = joined(nameTokens) {
                groupName = RFC2047Decoder.decodeWords(name)
            }
            if let comment = joined(commentTokens) {
                groupComment = RFC2047Decoder.decodeWords(comment)
            }
            if !mailTokens.isEmpty {
                let mail = mailTokens.joined()
                groupName = groupName.map { "\($0) \(mail)" } ?? mail
            }

            nameTokens.removeAll(keepingCapacity: true)
            mailTokens.removeAll(keepingCapacity: true)
            commentTokens.removeAll(keepingCapacity: true)
        }

        mutating func addGroup() {
            switch (groupName, addresses.isEmpty, groupComment) {
            case let (.some(name), false, .some(comment)):
                groups.append(
                    AddressGroup(
                        name: "\(name) (\(comment))",
                        addresses: addresses
                    )
                )
            case let (.some(name), false, _):
                groups.append(AddressGroup(name: name, addresses: addresses))
            case let (.none, false, comment):
                groups.append(AddressGroup(name: comment, addresses: addresses))
            case let (.some(name), true, _):
                groups.append(AddressGroup(name: name, addresses: []))
            default:
                return
            }

            groupName = nil
            groupComment = nil
            addresses.removeAll(keepingCapacity: true)
        }

        func joined(_ tokens: [String]) -> String? {
            guard !tokens.isEmpty else {
                return nil
            }
            return tokens.joined(separator: " ")
        }
    }
}

/// Best-effort parser for Message-ID, In-Reply-To, References, and Resent
/// message identifier fields.
enum RFCMessageIDParser {
    static func parse(_ source: String) -> [String] {
        let value = AddressParser.headerValue(source)
        var identifiers: [String] = []
        var token = ""
        var inIdentifier = false
        var sawAngle = false

        for character in value {
            switch character {
            case "<":
                inIdentifier = true
                sawAngle = true
                token = ""
            case ">" where inIdentifier:
                inIdentifier = false
                let identifier = token.trimmingCharacters(in: .whitespacesAndNewlines)
                if !identifier.isEmpty {
                    identifiers.append(identifier)
                }
                token = ""
            default:
                if inIdentifier {
                    token.append(character)
                }
            }
        }

        if !identifiers.isEmpty {
            return identifiers
        }

        if sawAngle {
            return []
        }

        let fallback = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? [] : [fallback]
    }
}
