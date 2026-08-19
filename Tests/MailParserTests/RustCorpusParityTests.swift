import Foundation
import Testing
@testable import MailParser

@Test
func rustMailParserCompleteMessageCorpusMatchesInLFAndCRLFForms() throws {
    let root = try #require(
        Bundle.module.url(
            forResource: "RustMailParser",
            withExtension: nil,
            subdirectory: "Fixtures"
        )
    )
    .appendingPathComponent("eml", isDirectory: true)

    var messagesTested = 0
    var mismatches: [String] = []

    for suite in ["rfc", "legacy", "thirdparty", "malformed"] {
        let directory = root.appendingPathComponent(suite, isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "eml" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for sourceURL in files {
            let original = try Data(contentsOf: sourceURL)
            for variant in CorpusVariant.allCases {
                let raw = variant.transform(original)
                let expectedURL = sourceURL
                    .deletingPathExtension()
                    .appendingPathExtension(variant.expectedExtension)
                let expectedData = try Data(contentsOf: expectedURL)
                let expected = try JSONSerialization.jsonObject(with: expectedData)

                guard let parsed = MessageParser().parse(raw) else {
                    mismatches.append("\(suite)/\(sourceURL.lastPathComponent) [\(variant)]: parser returned nil")
                    continue
                }
                let actual = RustProjection.message(parsed)
                if let difference = firstJSONDifference(
                    expected: expected,
                    actual: actual,
                    path: "$"
                ) {
                    mismatches.append(
                        "\(suite)/\(sourceURL.lastPathComponent) [\(variant)]: \(difference)"
                    )
                }
            }
            messagesTested += 1
        }
    }

    #expect(messagesTested == 107)
    #expect(
        mismatches.isEmpty,
        Comment(rawValue: mismatches.prefix(30).joined(separator: "\n"))
    )
}

private enum CorpusVariant: String, CaseIterable, CustomStringConvertible {
    case lf
    case crlf

    var description: String { rawValue }

    var expectedExtension: String {
        switch self {
        case .lf: "json"
        case .crlf: "crlf.json"
        }
    }

    func transform(_ data: Data) -> Data {
        switch self {
        case .lf:
            return Data(data.filter { $0 != 0x0D })
        case .crlf:
            var output = Data()
            output.reserveCapacity(data.count + data.count / 20)
            var previous: UInt8 = 0
            for byte in data {
                if byte == 0x0A, previous != 0x0D {
                    output.append(0x0D)
                }
                output.append(byte)
                previous = byte
            }
            return output
        }
    }
}

private enum RustProjection {
    static func message(_ message: Message) -> Any {
        return [
            "html_body": message.htmlBody,
            "text_body": message.textBody,
            "attachments": message.attachments,
            "parts": message.parts.map(part),
        ]
    }

    private static func part(_ part: MessagePart) -> Any {
        [
            "headers": part.headers.map(header),
            "is_encoding_problem": part.isEncodingProblem,
            "body": body(part.body),
            "offset_header": part.offsetHeader,
            "offset_body": part.offsetBody,
            "offset_end": part.offsetEnd,
        ]
    }

    private static func body(_ body: PartBody) -> Any {
        switch body {
        case .text(let value): return ["Text": value]
        case .html(let value): return ["Html": value]
        case .binary(let value): return ["Binary": value.map(Int.init)]
        case .inlineBinary(let value): return ["InlineBinary": value.map(Int.init)]
        case .message(let value): return ["Message": message(value)]
        case .multipart(let value): return ["Multipart": value]
        }
    }

    private static func header(_ header: Header) -> Any {
        [
            "name": name(header.name),
            "value": value(header.value),
            "offset_field": header.offsetField,
            "offset_start": header.offsetStart,
            "offset_end": header.offsetEnd,
        ]
    }

    private static func name(_ name: HeaderName) -> Any {
        if case .other(let value) = name {
            return ["other": value]
        }
        return name.rawValue.lowercased().replacingOccurrences(of: "-", with: "_")
    }

    private static func value(_ value: HeaderValue) -> Any {
        switch value {
        case .address(let value): return ["Address": address(value)]
        case .text(let value): return ["Text": value]
        case .textList(let value): return ["TextList": value]
        case .dateTime(let value): return ["DateTime": date(value)]
        case .contentType(let value): return ["ContentType": contentType(value)]
        case .received(let value): return ["Received": received(value)]
        case .empty: return "Empty"
        }
    }

    private static func address(_ address: Address) -> Any {
        switch address {
        case .list(let values):
            return ["List": values.map(mailAddress)]
        case .group(let values):
            return [
                "Group": values.map { group in
                    [
                        "name": optional(group.name),
                        "addresses": group.addresses.map(mailAddress),
                    ] as [String: Any]
                },
            ]
        }
    }

    private static func mailAddress(_ address: MailAddress) -> Any {
        [
            "name": optional(address.name),
            "address": optional(address.address),
        ]
    }

    private static func contentType(_ value: ContentType) -> Any {
        let attributes: Any = value.attributes.isEmpty
            ? NSNull()
            : value.attributes.map { ["name": $0.name, "value": $0.value] }
        return [
            "c_type": value.type,
            "c_subtype": optional(value.subtype),
            "attributes": attributes,
        ]
    }

    private static func date(_ value: MailDateTime) -> Any {
        [
            "year": value.year,
            "month": value.month,
            "day": value.day,
            "hour": value.hour,
            "minute": value.minute,
            "second": value.second,
            "tz_before_gmt": value.isNegativeOffset,
            "tz_hour": value.offsetHour,
            "tz_minute": value.offsetMinute,
        ]
    }

    private static func received(_ value: Received) -> Any {
        var result: [String: Any] = [
            "from": optional(value.from.map(host)),
            "from_ip": optional(value.fromIP),
            "from_iprev": optional(value.fromIPReverse),
            "by": optional(value.by.map(host)),
            "for_": optional(value.forRecipient),
            "with": optional(value.protocolValue.map(protocolName)),
            "tls_version": optional(value.tlsVersion.map(tlsName)),
            "tls_cipher": optional(value.tlsCipher),
            "ident": optional(value.ident),
            "helo": optional(value.helo.map(host)),
            "helo_cmd": optional(value.heloCommand.map(greetingName)),
            "via": optional(value.via),
            "date": optional(value.date.map(date)),
        ]
        if let id = value.id {
            result["id"] = id
        }
        return result
    }

    private static func host(_ value: MailParser.Host) -> Any {
        switch value {
        case .name(let value): ["Name": value]
        case .ipAddress(let value): ["IpAddr": value]
        }
    }

    private static func protocolName(_ value: MailProtocol) -> String {
        value.rawValue.uppercased()
    }

    private static func tlsName(_ value: TLSVersion) -> String {
        switch value {
        case .ssl2: "SSLv2"
        case .ssl3: "SSLv3"
        case .tls1_0: "TLSv1_0"
        case .tls1_1: "TLSv1_1"
        case .tls1_2: "TLSv1_2"
        case .tls1_3: "TLSv1_3"
        case .dtls1_0: "DTLSv1_0"
        case .dtls1_2: "DTLSv1_2"
        case .dtls1_3: "DTLSv1_3"
        }
    }

    private static func greetingName(_ value: Greeting) -> String {
        switch value {
        case .helo: "Helo"
        case .ehlo: "Ehlo"
        case .lhlo: "Lhlo"
        }
    }

    private static func optional<T>(_ value: T?) -> Any {
        if let value {
            return value
        }
        return NSNull()
    }
}

private func firstJSONDifference(
    expected: Any,
    actual: Any,
    path: String
) -> String? {
    if let expected = expected as? [String: Any],
       let actual = actual as? [String: Any]
    {
        let expectedKeys = Set(expected.keys)
        let actualKeys = Set(actual.keys)
        guard expectedKeys == actualKeys else {
            return "\(path) keys expected \(expectedKeys.sorted()), got \(actualKeys.sorted())"
        }
        for key in expectedKeys.sorted() {
            if let difference = firstJSONDifference(
                expected: expected[key] as Any,
                actual: actual[key] as Any,
                path: "\(path).\(key)"
            ) {
                return difference
            }
        }
        return nil
    }

    if let expected = expected as? [Any], let actual = actual as? [Any] {
        guard expected.count == actual.count else {
            return "\(path) count expected \(expected.count), got \(actual.count)"
        }
        for index in expected.indices {
            if let difference = firstJSONDifference(
                expected: expected[index],
                actual: actual[index],
                path: "\(path)[\(index)]"
            ) {
                return difference
            }
        }
        return nil
    }

    if expected is NSNull, actual is NSNull {
        return nil
    }
    if let expected = expected as? NSNumber,
       let actual = actual as? NSNumber,
       expected == actual
    {
        return nil
    }
    if let expected = expected as? String,
       let actual = actual as? String,
       expected == actual
    {
        return nil
    }
    return "\(path) expected \(String(reflecting: expected)), got \(String(reflecting: actual))"
}
