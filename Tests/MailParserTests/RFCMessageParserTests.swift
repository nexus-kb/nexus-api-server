//
//  RFCMessageParserTests.swift
//  MailParserTests
//
//  Created by Tanuj Ravi Rao on 8/13/26.
//

import Foundation
import Testing
@testable import MailParser

@Test
func parsesPlainTextMessage() throws {
    let raw = Data(
        """
        From: Example Person <person@example.com>
        To: list@example.com
        Cc: "Second Person" <second@example.com>
        Date: Wed, 12 Aug 2026 10:30:00 -0400
        Message-ID: <message@example.com>
        In-Reply-To: <parent@example.com>
        References: <root@example.com> <parent@example.com>
        Subject: [PATCH 1/2] Example
        Content-Type: text/plain; charset=utf-8

        Message body
        """.utf8
    )

    let message = try RFCMessageParser().parse(raw)

    #expect(message.messageID == "message@example.com")
    #expect(message.inReplyTo == "parent@example.com")
    #expect(
        message.references == [
            "root@example.com",
            "parent@example.com",
        ]
    )
    #expect(
        message.from == Mailbox(
            name: "Example Person",
            address: "person@example.com"
        )
    )
    #expect(
        message.to == [
            Mailbox(
                name: nil,
                address: "list@example.com"
            )
        ]
    )
    #expect(
        message.cc == [
            Mailbox(
                name: "Second Person",
                address: "second@example.com"
            )
        ]
    )
    #expect(message.textBody == "Message body")
}

@Test
func decodesFoldedEncodedSubject() throws {
    let raw = Data(
        """
        From: person@example.com
        Message-ID: <message@example.com>
        Subject: =?UTF-8?Q?Kernel_=E2=80=93?=
         =?UTF-8?Q?_patch?=

        Body
        """.utf8
    )

    let message = try RFCMessageParser().parse(raw)

    #expect(message.subject == "Kernel – patch")
}

@Test
func decodesMultipartPlainTextBodies() throws {
    let raw = Data(
        """
        From: person@example.com
        Message-ID: <message@example.com>
        Subject: Multipart
        MIME-Version: 1.0
        Content-Type: multipart/mixed; boundary="example-boundary"

        --example-boundary
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: quoted-printable

        first=20part
        --example-boundary
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: base64

        c2Vjb25kIHBhcnQ=
        --example-boundary--
        """.utf8
    )

    let message = try RFCMessageParser().parse(raw)

    #expect(
        message.textBody == "first part\nsecond part"
    )
}

@Test
func ignoresAttachmentsAndHTML() throws {
    let raw = Data(
        """
        From: person@example.com
        Message-ID: <message@example.com>
        Content-Type: multipart/mixed; boundary=boundary

        --boundary
        Content-Type: text/plain

        visible
        --boundary
        Content-Type: text/plain
        Content-Disposition: attachment; filename=example.patch

        hidden
        --boundary
        Content-Type: text/html

        <p>hidden</p>
        --boundary--
        """.utf8
    )

    let message = try RFCMessageParser().parse(raw)

    #expect(message.textBody == "visible")
}

@Test
func decodesHeaderlessMultipartTextPart() throws {
    let raw = Data(
        """
        From: Michael Chan <michael.chan@broadcom.com>
        To: bpf@vger.kernel.org
        Message-ID: <1648858872-14682-1-git-send-email-michael.chan@broadcom.com>
        Subject: [PATCH net 0/3] bnxt_en: XDP redirect fixes
        MIME-Version: 1.0
        Content-Type: multipart/signed; protocol="application/pkcs7-signature"; boundary="signed-boundary"

        --signed-boundary

        This series includes 3 fixes related to the XDP redirect code path in
        the driver.
        --signed-boundary
        Content-Type: application/pkcs7-signature; name="smime.p7s"
        Content-Transfer-Encoding: base64
        Content-Disposition: attachment; filename="smime.p7s"

        c2lnbmF0dXJl
        --signed-boundary--
        """.utf8
    )

    let message = try RFCMessageParser().parse(raw)

    #expect(
        message.messageID
            == "1648858872-14682-1-git-send-email-michael.chan@broadcom.com"
    )

    #expect(
        message.textBody
            == """
            This series includes 3 fixes related to the XDP redirect code path in
            the driver.
            """
    )
}

@Test
func usesEarliestHeaderBodySeparator() throws {
    var source =
        "From: person@example.com\n"

    source +=
        "Message-ID: <mixed-line-endings@example.com>\n"

    source +=
        "Subject: Mixed line endings\n"

    source += "\n"
    source += "First paragraph.\r\n"
    source += "\r\n"
    source += "Second paragraph."

    let raw = Data(source.utf8)
    let message = try RFCMessageParser().parse(raw)

    #expect(
        message.textBody
            == "First paragraph.\r\n\r\nSecond paragraph."
    )
}
