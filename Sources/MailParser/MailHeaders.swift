//
//  MailHeaders.swift
//  MailParser
//
//  Created by Tanuj Ravi Rao on 8/12/26.
//

import Foundation

public struct MailHeader: Sendable, Equatable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public struct MailHeaders: Sendable, Equatable {
    public let fields: [MailHeader]

    public init(fields: [MailHeader]) {
        self.fields = fields
    }

    public func values(named name: String) -> [String] {
        fields.compactMap { field in
            field.name.caseInsensitiveCompare(name) == .orderedSame
                ? field.value
                : nil
        }
    }

    public func firstValue(named name: String) -> String? {
        values(named: name).first
    }
}

struct MessageEntity {
    let headers: MailHeaders
    let body: Data
}

enum MessageSyntax {
    static func parseEntity(_ data: Data) throws -> MessageEntity {
        guard !data.isEmpty else {
            throw MailParserError.emptyMessage
        }

        let (headerData, body) = splitHeaderAndBody(data)

        return MessageEntity(
            headers: try parseHeaders(headerData),
            body: body
        )
    }

    private static func splitHeaderAndBody(
        _ data: Data
    ) -> (Data, Data) {
        let separator: (offset: Int, length: Int)? =
            data.withUnsafeBytes { rawBuffer in
                let bytes = rawBuffer.bindMemory(
                    to: UInt8.self
                )

                // A MIME body part may legally contain no
                // part headers. Its header section is then
                // represented by one leading line ending.
                if bytes.count >= 2,
                    bytes[0] == 0x0D,
                    bytes[1] == 0x0A
                {
                    return (0, 2)
                }

                if bytes.first == 0x0A
                    || bytes.first == 0x0D
                {
                    return (0, 1)
                }

                guard bytes.count >= 2 else {
                    return nil
                }

                var offset = 0

                while offset < bytes.count - 1 {
                    switch bytes[offset] {
                    case 0x0A:
                        // \n\n
                        if bytes[offset + 1] == 0x0A {
                            return (offset, 2)
                        }

                    case 0x0D:
                        // \r\r
                        if bytes[offset + 1] == 0x0D {
                            return (offset, 2)
                        }

                        // \r\n\r\n
                        if offset + 3 < bytes.count,
                            bytes[offset + 1] == 0x0A,
                            bytes[offset + 2] == 0x0D,
                            bytes[offset + 3] == 0x0A
                        {
                            return (offset, 4)
                        }

                    default:
                        break
                    }

                    offset += 1
                }

                return nil
            }

        guard let separator else {
            return (data, Data())
        }

        let separatorStart = data.index(
            data.startIndex,
            offsetBy: separator.offset
        )

        let bodyStart = data.index(
            separatorStart,
            offsetBy: separator.length
        )

        return (
            data[..<separatorStart],
            data[bodyStart...]
        )
    }

    private static func normalizedHeaderText(
        _ data: Data
    ) -> String {
        let isolatedCarriageReturnReplacement =
            data.contains(0x0A) ? " " : "\n"

        return String(
            decoding: data,
            as: UTF8.self
        )
        .replacingOccurrences(
            of: "\r\n",
            with: "\n"
        )
        .replacingOccurrences(
            of: "\r",
            with: isolatedCarriageReturnReplacement
        )
    }

    private static func parseHeaders(
        _ data: Data
    ) throws -> MailHeaders {
        let text = normalizedHeaderText(data)

        var fields: [MailHeader] = []
        var currentName: String?
        var currentValue = ""

        func finishCurrentField() {
            guard let currentName else {
                return
            }

            fields.append(
                MailHeader(
                    name: currentName,
                    value: currentValue.trimmingCharacters(in: .whitespaces)
                )
            )
        }

        for line in text.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ) {
//            Check if line is continuation of previous header field
            if line.first == " " || line.first == "\t" {
                guard currentName != nil else {
                    continue
                }

                currentValue += " "
                currentValue += line.trimmingCharacters(in: .whitespaces)
                continue
            }

            finishCurrentField()

            guard let colon = line.firstIndex(of: ":") else {
//            DEBUG ONLY: If no colon, but all-whitespace,
//            we did an oopsy and something is broken.
                if line.allSatisfy({ $0.isWhitespace }) {
                    currentName = nil
                    currentValue = ""
                    continue
                }
//              If no colon and not a separator, header broken
                throw MailParserError.malformedHeader(String(line))
            }
//            Grab name
            currentName = String(line[..<colon])
                .trimmingCharacters(in: .whitespaces)
//            Grab value
            currentValue = String(
                line[line.index(after: colon)...]
            ).trimmingCharacters(in: .whitespaces)
        }

        finishCurrentField()
        return MailHeaders(fields: fields)
    }
}
