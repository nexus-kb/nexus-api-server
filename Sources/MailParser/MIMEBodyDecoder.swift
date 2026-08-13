//
//  MIMEBodyDecoder.swift
//  MailParser
//
//  Created by Tanuj Ravi Rao on 8/13/26.
//

import Foundation

enum MIMEBodyDecoder {
    static func decodeTextBodies(
        from entity: MessageEntity
    ) throws -> [String] {
        let contentType = HeaderParameterParser.parse(
            entity.headers.firstValue(
                named: "Content-Type"
            )
        )

        let mediaType = contentType.value.isEmpty
            ? "text/plain"
            : contentType.value

        let disposition = HeaderParameterParser.parse(
            entity.headers.firstValue(
                named: "Content-Disposition"
            )
        )

        if disposition.value == "attachment" {
            return []
        }

        if mediaType.hasPrefix("multipart/") {
            guard let boundary =
                    contentType.parameters["boundary"],
                  !boundary.isEmpty
            else {
                throw MailParserError
                    .malformedMultipartBoundary
            }

            return try splitMultipartBody(
                entity.body,
                boundary: boundary
            ).flatMap { part in
                try decodeTextBodies(
                    from: MessageSyntax.parseEntity(part)
                )
            }
        }

        guard mediaType == "text/plain" else {
            return []
        }

        let transferEncoding = entity.headers
            .firstValue(
                named: "Content-Transfer-Encoding"
            )?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .lowercased()

        let decodedBody: Data

        switch transferEncoding {
        case "base64":
            guard let decoded = Data(
                base64Encoded: entity.body,
                options: .ignoreUnknownCharacters
            ) else {
                throw MailParserError.invalidBase64Body
            }

            decodedBody = decoded

        case "quoted-printable":
            decodedBody =
                HeaderValueDecoder.decodeQuotedPrintable(
                    entity.body
                )

        default:
            decodedBody = entity.body
        }

        return [
            HeaderValueDecoder.decodeText(
                decodedBody,
                charset: contentType.parameters["charset"]
            )
        ]
    }

    private static func splitMultipartBody(
        _ data: Data,
        boundary: String
    ) -> [Data] {
        let bytes = [UInt8](data)
        let openingBoundary = Array(
            "--\(boundary)".utf8
        )
        let closingBoundary = Array(
            "--\(boundary)--".utf8
        )

        var parts: [Data] = []
        var currentPart: [UInt8]?
        var lineStart = 0

        while lineStart < bytes.count {
            var lineEnd = lineStart

            while lineEnd < bytes.count,
                  bytes[lineEnd] != 10
            {
                lineEnd += 1
            }

            var contentEnd = lineEnd

            if contentEnd > lineStart,
               bytes[contentEnd - 1] == 13
            {
                contentEnd -= 1
            }

            let line = Array(
                bytes[lineStart..<contentEnd]
            )

            if line == openingBoundary
                || line == closingBoundary
            {
                if let completed = currentPart {
                    parts.append(
                        trimTrailingLineBreak(
                            Data(completed)
                        )
                    )
                }

                if line == closingBoundary {
                    currentPart = nil
                    break
                }

                currentPart = []
            } else if currentPart != nil {
                currentPart?.append(
                    contentsOf: bytes[lineStart..<lineEnd]
                )

                if lineEnd < bytes.count {
                    currentPart?.append(bytes[lineEnd])
                }
            }

            lineStart = lineEnd < bytes.count
                ? lineEnd + 1
                : bytes.count
        }

        if let currentPart, !currentPart.isEmpty {
            parts.append(
                trimTrailingLineBreak(
                    Data(currentPart)
                )
            )
        }

        return parts
    }

    private static func trimTrailingLineBreak(
        _ data: Data
    ) -> Data {
        var bytes = [UInt8](data)

        if bytes.last == 10 {
            bytes.removeLast()
        }

        if bytes.last == 13 {
            bytes.removeLast()
        }

        return Data(bytes)
    }
}
