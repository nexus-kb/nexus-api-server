import Foundation
import Testing
@testable import MailParser

@Test
func parsesAddressGroupsCommentsAndObsoleteForms() throws {
    let parsed = try #require(
        AddressParser.parse(
            "Friends (team): John Doe <john(comment)@example.com>, "
                + "postmaster (The Postmaster);"
        )
    )
    guard case .group(let groups) = parsed else {
        Issue.record("Expected an address group")
        return
    }

    #expect(groups.count == 1)
    #expect(groups[0].name == "Friends (team)")
    #expect(groups[0].addresses == [
        MailAddress(name: "John Doe (comment)", address: "john@example.com"),
        MailAddress(name: "The Postmaster", address: "postmaster"),
    ])
    #expect(AddressParser.localPart(of: "user@exämple.com") == "user")
    #expect(AddressParser.domain(of: "user@exämple.com") == "exämple.com")
    #expect(AddressParser.userPart(of: "user+detail@example.com") == "user")
    #expect(AddressParser.detailPart(of: "user+detail@example.com") == "detail")
    #expect(AddressParser.userPart(of: "user+one+two@example.com") == "user")
    #expect(AddressParser.detailPart(of: "user+one+two@example.com") == "two")
    #expect(AddressParser.userPart(of: "+detail@example.com") == nil)
    #expect(AddressParser.detailPart(of: "+detail@example.com") == "detail")
    #expect(AddressParser.detailPart(of: "user+@example.com") == "")
    #expect(AddressParser.userPart(of: "user+détail@example.com") == "user")
    #expect(AddressParser.detailPart(of: "user+détail@example.com") == nil)
}

@Test
func parsesTimezonePreservingRFC5322AndRFC3339Dates() throws {
    let date = try #require(
        MailDateTime.parseRFC5322("Tue, 18 Aug 2026 12:34:56 -0430")
    )

    #expect(date.year == 2026)
    #expect(date.month == 8)
    #expect(date.day == 18)
    #expect(date.isNegativeOffset)
    #expect(date.offsetHour == 4)
    #expect(date.offsetMinute == 30)
    #expect(date.rfc3339 == "2026-08-18T12:34:56-04:30")
    #expect(date.foundationDate != nil)

    let obsolete = try #require(
        MailDateTime.parseRFC5322("18 Aug 26 12:34:56 EDT")
    )
    #expect(obsolete.year == 2026)
    #expect(obsolete.isNegativeOffset)
    #expect(obsolete.offsetHour == 4)
}

@Test
func parsesStructuredReceivedTraceInformation() throws {
    let raw = Data(
        """
        Received: from out-25.smtp.example (mx.example. [192.0.2.25])
         (using TLSv1.3 with cipher TLS_AES_256_GCM_SHA384)
         by mail.example with ESMTPS id ABC123 for <user@example.com>;
         Tue, 18 Aug 2026 12:34:56 -0400
        Subject: trace

        body
        """.utf8
    )
    let trace = try #require(MessageParser().parse(raw)?.received)

    #expect(trace.from == .name("out-25.smtp.example"))
    #expect(trace.fromIP == "192.0.2.25")
    #expect(trace.fromIPReverse == "mx.example.")
    #expect(trace.by == .name("mail.example"))
    #expect(trace.forRecipient == "user@example.com")
    #expect(trace.protocolValue == .esmtps)
    #expect(trace.tlsVersion == .tls1_3)
    #expect(trace.tlsCipher == "TLS_AES_256_GCM_SHA384")
    #expect(trace.id == "ABC123")
    #expect(trace.date?.isNegativeOffset == true)
    #expect(trace.date?.offsetHour == 4)
}

@Test
func receivedDateMinimumIntegerZoneDoesNotTrap() throws {
    let trace = try #require(
        ReceivedParser.parse(
            "from sender.example by receiver.example; "
                + "1 Jan 2020 00:00:00 -9223372036854775808"
        )
    )

    // Matches mail-parser's release-mode wrapping casts for this pathological
    // input while remaining safe in Swift debug builds.
    #expect(trace.date?.isNegativeOffset == true)
    #expect(trace.date?.offsetHour == 82)
    #expect(trace.date?.offsetMinute == 248)
}

@Test
func receivedIPLiteralValidationAndFormattingMatchesRust() throws {
    let expanded = try #require(
        ReceivedParser.parse(
            "from [2001:0DB8:0000:0000:0000:FF00:0042:8329] by mx.example"
        )
    )
    #expect(expanded.from == .ipAddress("2001:db8::ff00:42:8329"))

    let ipv4 = try #require(
        ReceivedParser.parse("from [192.0.2.1] by mx.example")
    )
    #expect(ipv4.from == .ipAddress("192.0.2.1"))

    let labeled = try #require(
        ReceivedParser.parse("from mx.example ([IPv6:::1]) by receiver.example")
    )
    #expect(labeled.fromIP == "::1")

    let malformed = [
        "192.0.2.001",
        "192.0.2.256",
        "1:2:3:4:5:6:7",
        "1:2:3:4:5:6:7:8:9",
        "1::2::3",
        "12345::1",
        "1:2:3:4:5::6:7:8",
        "fe80::1%eth0",
    ]
    for value in malformed {
        let trace = try #require(
            ReceivedParser.parse("from [\(value)] by mx.example")
        )
        #expect(trace.from == .name(value), Comment(rawValue: value))
    }
}

@Test
func receivedTLSVersionRecognitionIsTokenExact() throws {
    let valid = try #require(
        ReceivedParser.parse(
            "from sender.example (using TLSv1.2) by receiver.example"
        )
    )
    #expect(valid.tlsVersion == .tls1_2)

    let nearMatch = try #require(
        ReceivedParser.parse(
            "from sender.example (using XTLS1.2Y) by receiver.example"
        )
    )
    #expect(nearMatch.tlsVersion == nil)
}

@Test
func receivedEmailAndDomainTokenPredicatesMatchRust() throws {
    // Differential expectations from mail-parser 0.11.6 at b4366b7.
    let validEmail = try #require(
        ReceivedParser.parse("from mx.example (a@b) by receiver.example")
    )
    #expect(validEmail.ident == "a@b")

    for value in ["@", "a@@b", "123@456", "例@测试"] {
        let implicitIdent = try #require(
            ReceivedParser.parse(
                "from mx.example (\(value)) by receiver.example"
            )
        )
        #expect(implicitIdent.ident == nil, Comment(rawValue: value))

        let recipient = try #require(
            ReceivedParser.parse(
                "from mx.example by receiver.example for <\(value)>"
            )
        )
        #expect(recipient.forRecipient == nil, Comment(rawValue: value))
    }

    let validRecipient = try #require(
        ReceivedParser.parse(
            "from mx.example by receiver.example for <a@b>"
        )
    )
    #expect(validRecipient.forRecipient == "a@b")

    let mixedUnicodeDomain = try #require(
        ReceivedParser.parse(
            "from mx.example (müller.example) by receiver.example"
        )
    )
    #expect(mixedUnicodeDomain.fromIPReverse == "müller.example")

    for value in ["evil!host.example", "host_name.example", "例.测试"] {
        let trace = try #require(
            ReceivedParser.parse(
                "from mx.example (\(value)) by receiver.example"
            )
        )
        #expect(trace.fromIPReverse == nil, Comment(rawValue: value))
    }
}

@Test
func extractsLocalizedRFCThreadNames() {
    // Ported from mail-parser 0.11.6 at b4366b7:
    // src/parsers/fields/thread.rs.
    let threadNameCases: [(input: String, expected: String)] = [
        ("re: hello", "hello"),
        ("re:re: hello", "hello"),
        ("re:fwd: hello", "hello"),
        ("fwd[5]:re[5]: hello", "hello"),
        ("fwd[99]:  re[40]: hello", "hello"),
        (": hello", ": hello"),
        ("z: hello", "z: hello"),
        ("re:: hello", ": hello"),
        ("[10] hello", "hello"),
        ("fwd[a]: hello", "hello"),
        ("re:", ""),
        ("re::", ":"),
        ("", ""),
        (" ", ""),
        ("回复: 轉寄: 轉寄", "轉寄"),
        ("aw[50]: wg: aw[1]: hallo", "hallo"),
        ("res: rv: enc: továbbítás: ", ""),
        ("[fwd: hello world]", "hello world"),
        ("re: enc: re[5]: [fwd: hello world]", "hello world"),
        ("[fwd: re: fw: hello world]", "hello world"),
        ("[fwd: hello world]: another text", ": another text"),
        ("[fwd: re: fwd:] another text", "another text"),
        ("[hello world]", "[hello world]"),
        ("re: fwd[9]: [hello world]", "[hello world]"),
        ("[mailing-list] hello world", "hello world"),
        ("[mailing-list] re: hello world", "hello world"),
        ("[mailing-list] wg[8]:re:  hello world", "hello world"),
        ("hello [world]", "hello [world]"),
        (" [hello] [world] ", "[hello] [world]"),
        ("[mailing-list] hello [world]", "hello [world]"),
        ("[hello [world]", "[hello [world]"),
        ("[]hello [world]", "hello [world]"),
        ("[fwd: re: re:] fwd[6]:re:  fw:", ""),
        ("[fwd hello] world hello", "world hello"),
        ("[fwd: مرحبا بالعالم]", "مرحبا بالعالم"),
        ("[fwd: hello world] مرحبا بالعالم", "مرحبا بالعالم"),
        ("  hello world  ", "hello world"),
        (
            "[mailing-list] wg[8]:re:  hello world (fwd)(fwd)",
            "hello world"
        ),
        ("[fwd: re: fw: hello world (fwd)]", "hello world"),
        (
            "res: rv: enc: továbbítás: hello world (doorst)",
            "hello world"
        ),
        ("[fwd: re: re: (fwd)] fwd[6]:re:  fw: (fwd)", ""),
    ]
    let trailingForwardCases: [(input: String, expected: String)] = [
        ("hello (fwd)", "hello"),
        (" hello (fwd)(fwd)", "hello"),
        ("hello (wg) (fwd) (fwd)", "hello"),
        ("(fwd)(fwd)", ""),
        ("(fwd)hello(fwd)", "(fwd)hello"),
        ("  hello  ", "hello"),
        ("  hello world   ", "hello world"),
        ("", ""),
        ("    ", ""),
        ("hello ()(fwd)", "hello ()"),
        ("(hello)", "(hello)"),
        ("hello () (fwd) ()(fwd)", "hello () (fwd) ()"),
        (")(", ")("),
        (" 你好世界(fwd) ", "你好世界"),
        ("你好世界 (回覆)", "你好世界"),
        ("hello(fwd", "hello(fwd"),
        ("hello(fwd))", "hello(fwd))"),
    ]

    #expect(threadNameCases.count == 41)
    #expect(trailingForwardCases.count == 17)
    for testCase in threadNameCases + trailingForwardCases {
        let context = Comment(rawValue: "input: \(testCase.input.debugDescription)")
        #expect(
            ThreadNameParser.threadName(testCase.input) == testCase.expected,
            context
        )
        #expect(
            ThreadNameParser.baseSubject(testCase.input) == testCase.expected,
            context
        )
    }
}

@Test
func parsesRFC2231MIMEParametersAndEncodedWords() throws {
    let raw = Data(
        """
        Content-Type: application/pdf;
         filename*0*=iso-8859-1'es'%D1and%FA;
         filename*1*=iso-8859-1'%20r%E1pido.pdf

        data
        """.utf8
    )
    let contentType = try #require(
        MessageParser().parse(raw)?.rootPart?.contentType
    )

    #expect(contentType.type == "application")
    #expect(contentType.subtype == "pdf")
    #expect(contentType.attribute(named: "filename-language") == "es")
    #expect(contentType.attribute(named: "filename") == "Ñandú rápido.pdf")
}

@Test
func parsesAdversarialFoldedMIMEParametersWithLeadingStars() throws {
    let leadingStars = String(repeating: "*", count: 16_384)
    let ordinaryParameters = (0..<2_048).map { index in
        "p\(index)=v\(index)"
    }
    let sections = [
        leadingStars + "filename*=utf-8''large%20file.bin",
    ] + ordinaryParameters
    let source = "application/octet-stream\r\n "
        + sections.joined(separator: "\r\n ")

    let contentType = try #require(MIMEParameterParser.parse(source))

    #expect(contentType.attribute(named: "filename") == "large file.bin")
    #expect(contentType.attribute(named: "p0") == "v0")
    #expect(contentType.attribute(named: "p2047") == "v2047")
    #expect(contentType.attributes.count == 2_049)
}

@Test
func combinesLargeMIMEContinuationsWithoutChangingFirstValueSemantics() throws {
    let fillerCount = 2_048
    let continuationCount = 4_096
    let fragment = "abcdefgh"
    var sections = (0..<fillerCount).map { index in
        "p\(index)=v\(index)"
    }
    sections.append("filename*0*=utf-8'en'start")
    sections.append("filename=duplicate")
    sections.append(
        contentsOf: (1...continuationCount).map { position in
            "filename*\(position)*=utf-8'en'\(fragment)"
        }
    )

    let contentType = try #require(
        MIMEParameterParser.parse(
            "application/octet-stream; " + sections.joined(separator: "; ")
        )
    )
    let expected = "start"
        + String(repeating: fragment, count: continuationCount)

    #expect(contentType.attribute(named: "filename-language") == "en")
    #expect(contentType.attribute(named: "filename") == expected)
    #expect(
        contentType.attributes
            .filter { $0.name == "filename" }
            .map(\.value) == [expected, "duplicate"]
    )
    #expect(
        contentType.attributes.suffix(3).map(\.name)
            == ["filename-language", "filename", "filename"]
    )
    #expect(contentType.attributes.count == fillerCount + 3)
}

@Test
func extractsEveryBracketedMessageIdentifierAndMalformedFallback() throws {
    let raw = Data(
        """
        Message-ID: malformed@example.com
        In-Reply-To: <one@example.com> <two@example.com>
        References: <root@example.com> <one@example.com>

        body
        """.utf8
    )
    let message = try #require(MessageParser().parse(raw))

    #expect(message.messageID == "malformed@example.com")
    #expect(message.inReplyToIDs == ["one@example.com", "two@example.com"])
    #expect(message.referenceIDs == ["root@example.com", "one@example.com"])
}

@Test
func matchesTheCompleteUpstreamStructuredFieldCorpusInLFAndCRLF() throws {
    let root = try #require(
        Bundle.module.url(
            forResource: "RustMailParser",
            withExtension: nil,
            subdirectory: "Fixtures"
        )
    )

    var casesTested = 0
    var mismatches: [String] = []
    for fixtureName in [
        "address",
        "date",
        "received",
        "content_type",
        "id",
        "unstructured",
        "list",
    ] {
        let url = root.appendingPathComponent("\(fixtureName).json")
        let data = try Data(contentsOf: url)
        let fixtures = try #require(
            JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        )

        for (index, fixture) in fixtures.enumerated() {
            let header = try #require(fixture["header"] as? String)
            let expected = fixture["expected"] ?? NSNull()

            for (variant, value) in fieldVariants(header) {
                let actual: Any
                switch fixtureName {
                case "address":
                    actual = AddressParser.parse(value).map(addressProjection) ?? NSNull()
                case "date":
                    actual = MailDateParser.parse(value).map(dateProjection) ?? NSNull()
                case "received":
                    actual = ReceivedParser.parse(value).map(receivedProjection) ?? NSNull()
                case "content_type":
                    actual = MIMEParameterParser.parse(value).map(contentProjection) ?? NSNull()
                case "unstructured":
                    actual = parsedFixtureHeader(
                        name: "Subject",
                        value: value
                    )?.text ?? NSNull()
                case "list":
                    let parsed = parsedFixtureHeader(
                        name: "Keywords",
                        value: value
                    )
                    actual = parsed.map(\.textValues) ?? NSNull()
                default:
                    let identifiers = RFCMessageIDParser.parse(value)
                    actual = identifiers.isEmpty ? NSNull() : identifiers
                }

                let normalizedExpected = fixtureName == "received"
                    ? removingNullDictionaryValues(expected)
                    : normalizedContentExpected(expected, fixtureName: fixtureName)
                let normalizedActual = fixtureName == "received"
                    ? removingNullDictionaryValues(actual)
                    : actual
                if canonicalJSON(normalizedActual) != canonicalJSON(normalizedExpected) {
                    mismatches.append("\(fixtureName)[\(index)] [\(variant)]")
                }
            }
        }
        casesTested += fixtures.count
    }

    #expect(casesTested == 443)
    #expect(
        mismatches.isEmpty,
        Comment(rawValue: mismatches.prefix(30).joined(separator: ", "))
    )
}

private func parsedFixtureHeader(
    name: String,
    value: String
) -> HeaderValue? {
    let newline = value.contains("\r\n") ? "\r\n" : "\n"
    let raw = Data("\(name):\(value)\(newline)".utf8)
    return MessageParser().parseHeaders(raw)?.header(named: name)
}

private func fieldVariants(_ source: String) -> [(String, String)] {
    let lf = source
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
    return [
        ("lf", lf),
        ("crlf", lf.replacingOccurrences(of: "\n", with: "\r\n")),
    ]
}

private func addressProjection(_ address: Address) -> Any {
    func mailbox(_ value: MailAddress) -> Any {
        [
            "name": optionalField(value.name),
            "address": optionalField(value.address),
        ] as [String: Any]
    }

    switch address {
    case .list(let values):
        return ["List": values.map(mailbox)]
    case .group(let groups):
        return [
            "Group": groups.map { group in
                [
                    "name": group.name.map { $0 as Any } ?? NSNull(),
                    "addresses": group.addresses.map(mailbox),
                ] as [String: Any]
            },
        ]
    }
}

private func dateProjection(_ value: MailDateTime) -> Any {
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

private func contentProjection(_ value: ContentType) -> Any {
    let attributes: Any = value.attributes.isEmpty
        ? NSNull()
        : value.attributes.map { [$0.name, $0.value] }
    return [
        "c_type": value.type,
        "c_subtype": optionalField(value.subtype),
        "attributes": attributes,
    ] as [String: Any]
}

private func receivedProjection(_ value: Received) -> Any {
    var result: [String: Any] = [:]
    if let value = value.from { result["from"] = hostProjection(value) }
    if let value = value.fromIP { result["from_ip"] = value }
    if let value = value.fromIPReverse { result["from_iprev"] = value }
    if let value = value.by { result["by"] = hostProjection(value) }
    if let value = value.forRecipient { result["for_"] = value }
    if let value = value.protocolValue {
        result["with"] = value == .local ? "Local" : value.rawValue.uppercased()
    }
    if let value = value.tlsVersion { result["tls_version"] = tlsProjection(value) }
    if let value = value.tlsCipher { result["tls_cipher"] = value }
    if let value = value.id { result["id"] = value }
    if let value = value.ident { result["ident"] = value }
    if let value = value.helo { result["helo"] = hostProjection(value) }
    if let value = value.heloCommand {
        result["helo_cmd"] = switch value {
        case .helo: "Helo"
        case .ehlo: "Ehlo"
        case .lhlo: "Lhlo"
        }
    }
    if let value = value.via { result["via"] = value }
    if let value = value.date { result["date"] = dateProjection(value) }
    return result
}

private func hostProjection(_ value: MailParser.Host) -> Any {
    switch value {
    case .name(let value): ["Name": value]
    case .ipAddress(let value): ["IpAddr": value]
    }
}

private func tlsProjection(_ value: TLSVersion) -> String {
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

private func normalizedContentExpected(
    _ value: Any,
    fixtureName: String
) -> Any {
    guard fixtureName == "content_type",
          var dictionary = value as? [String: Any]
    else {
        return value
    }
    if dictionary["attributes"] == nil {
        dictionary["attributes"] = NSNull()
    }
    if dictionary["c_subtype"] == nil {
        dictionary["c_subtype"] = NSNull()
    }
    return dictionary
}

private func removingNullDictionaryValues(_ value: Any) -> Any {
    if let dictionary = value as? [String: Any] {
        return dictionary.reduce(into: [String: Any]()) { result, element in
            guard !(element.value is NSNull) else { return }
            result[element.key] = removingNullDictionaryValues(element.value)
        }
    }
    if let array = value as? [Any] {
        return array.map(removingNullDictionaryValues)
    }
    return value
}

private func canonicalJSON(_ value: Any) -> Data {
    try! JSONSerialization.data(
        withJSONObject: value,
        options: [.fragmentsAllowed, .sortedKeys]
    )
}

private func optionalField<T>(_ value: T?) -> Any {
    if let value {
        return value
    }
    return NSNull()
}
