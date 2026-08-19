import Foundation
import Testing
@testable import NexusKb

@Test
func normalizesQuotedPrintableNULForPostgres() throws {
    let raw = Data(
        """
        From: syzbot <syzbot@example.com>
        To: bpf@vger.kernel.org
        Message-ID: <nul-body@example.com>
        Subject: [PATCH] Reproducer
        MIME-Version: 1.0
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: quoted-printable

        Please remove unsupported %=00 in format string
        diff --git a/example.c b/example.c
        --- a/example.c
        +++ b/example.c
        @@ -1 +1 @@
        -old
        +new
        """.utf8
    )

    let parsed =
        try IngestMessageParser().parse(raw)

    #expect(
        parsed.message.textBody.contains(
            "\u{0000}"
        )
    )

    #expect(
        parsed.patch.diff?.contains(
            "\u{0000}"
        ) == true
    )

    let normalized =
        PostgresTextNormalizer.normalize(
            parsed
        )

    #expect(
        !normalized.message.textBody.contains(
            "\u{0000}"
        )
    )

    #expect(
        normalized.message.textBody.contains(
            "%\\0 in format string"
        )
    )

    #expect(
        normalized.patch.diff?.contains(
            "\u{0000}"
        ) == false
    )

    #expect(
        normalized.patch.diff?.contains(
            "%\\0 in format string"
        ) == true
    )
}

@Test
func leavesOrdinaryPostgresTextUnchanged() {
    let value =
        "ordinary UTF-8: café — kernel"

    #expect(
        PostgresTextNormalizer.normalize(
            value
        ) == value
    )
}

@Test
func normalizesEveryEmbeddedNUL() {
    let value =
        "one\u{0000}two\u{0000}three"

    #expect(
        PostgresTextNormalizer.normalize(
            value
        ) == "one\\0two\\0three"
    )
}
