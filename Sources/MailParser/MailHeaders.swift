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
        let bytes = [UInt8](data)

        // A MIME body part may legally contain no part
        // headers. In that case its header section is
        // represented by a single leading line ending.
        if bytes.starts(with: [13, 10]) {
            return (
                Data(),
                Data(bytes.dropFirst(2))
            )
        }

        if bytes.first == 10
            || bytes.first == 13
        {
            return (
                Data(),
                Data(bytes.dropFirst())
            )
        }

        //        [13, 10, 13, 10]  →  \r\n\r\n CRLF separator
        //        [10, 10]          →  \n\n UNIX/LF-only mail
        //        [13, 13]          →  \r\r old/non-standard CR-only mail
        let separators: [[UInt8]] = [
            [13, 10, 13, 10],
            [10, 10],
            [13, 13],
        ]

        var selectedIndex: Int?
        var selectedLength = 0

        for separator in separators {
            guard let index = firstIndex(
                of: separator,
                in: bytes
            ) else {
                continue
            }

            if selectedIndex.map({
                index < $0
            }) ?? true {
                selectedIndex = index
                selectedLength = separator.count
            }
        }

        guard let selectedIndex else {
            return (data, Data())
        }

        return (
            Data(bytes[..<selectedIndex]),
            Data(
                bytes[
                    (selectedIndex + selectedLength)...
                ]
            )
        )
    }

//    Finds first occurance of needle in haystack using a sequential scan
    private static func firstIndex(
        of needle: [UInt8],
        in haystack: [UInt8]
    ) -> Int? {
        guard haystack.count >= needle.count else {
            return nil
        }

        for index in 0...(haystack.count - needle.count) {
            let candidate = haystack[
                index..<(index + needle.count)
            ]

            if candidate.elementsEqual(needle) {
                return index
            }
        }

        return nil
    }

    private static func parseHeaders(
        _ data: Data
    ) throws -> MailHeaders {
        let text = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

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
