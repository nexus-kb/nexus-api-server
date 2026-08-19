# MailParser

`MailParser` is the SwiftPM library product for parsing one RFC 5322 message
and its MIME tree. Its compatibility target is Stalwart Labs' Rust
`mail-parser` 0.11.6 at commit `b4366b7`.

Implementation and performance evidence is recorded in the
[MailParser verification report](mail-parser-verification.md).

The parser is immutable, nonthrowing, and independent of Vapor and SwiftNIO:

```swift
import Foundation
import MailParser

let parser = MessageParser()

guard let message = parser.parse(rawData) else {
    // No usable header block or message entity was found.
    return
}

let subject = message.subject
let sender = message.from?.first
let text = message.bodyText(at: 0)
let preview = message.bodyPreview(maxLength: 280)
```

`parse(_:)` returns `nil` only when it cannot construct a usable message.
Missing fields, including `Message-ID`, do not make a message invalid.
Malformed bodies and failed transfer decoding are retained in the result and
reported through `MessagePart.isEncodingProblem`.

Use `parseHeaders(_:)` when only the header block is needed:

```swift
let headersOnly = MessageParser().parseHeaders(rawData)
```

Both methods have `Data` and generic `Collection<UInt8>` overloads. The
generic overload makes a single owned `Data` value for the result. For
example, a Vapor application can pass an NIO `ByteBuffer` view without adding
SwiftNIO as a dependency of `MailParser`:

```swift
let message = MessageParser().parse(buffer.readableBytesView)
```

The parser accepts CRLF and LF line endings. Bare CR is not treated as a line
terminator.

## Complete result model

`Message` retains:

- `rawMessage`, the owned message bytes;
- `parts`, a flat, depth-first table of `MessagePart` values;
- the `textBody`, `htmlBody`, and `attachments` part-ID selections.

A `MessagePartID` is an index into `Message.parts`. Use `part(at:)`,
`textPart(at:)`, `htmlPart(at:)`, or `attachment(at:)` instead of indexing
unchecked. The corresponding counts and collections are available through
`textBodyCount`, `htmlBodyCount`, `attachmentCount`, `textParts`, `htmlParts`,
and `attachmentParts`.

Each `MessagePart` retains ordered typed headers, decoded transfer encoding,
an encoding-problem flag, and its body as one of:

```swift
public indirect enum PartBody {
    case text(String)
    case html(String)
    case binary(Data)
    case inlineBinary(Data)
    case message(Message)
    case multipart([MessagePartID])
}
```

`MessagePart.offsetHeader`, `offsetBody`, and `offsetEnd` describe half-open
byte ranges in the part's `Message.rawMessage`. `Header.offsetField` points to
the raw field-name start, while `offsetStart` and `offsetEnd` delimit the raw,
possibly folded value. Direct unencoded nested messages deliberately share
the outer message's raw buffer and coordinate space. Transfer-decoded nested
messages own the decoded entity bytes and use that byte space for their
offsets.

All stored public result types are `Sendable`, `Equatable`, and `Codable`.
Enums with associated values use explicit tagged encoding, and serialization
includes raw data, offsets, transfer metadata, and recursively nested
messages:

```swift
let data = try JSONEncoder().encode(message)
let decoded = try JSONDecoder().decode(Message.self, from: data)
precondition(decoded == message)
```

This is a complete parser result, not the smaller Nexus persistence model. In
particular, retaining a `Message` also retains its raw input and attachment
data.

## Headers and structured fields

Headers remain ordered and repeated. Singular access returns the last
occurrence; plural access preserves source order:

```swift
let subject = message.header(.subject)
let allReceived = message.headerValues(.received)
let extensionValue = message.header(named: "X-Original-From")
let rawValues = message.rawHeaderValues(named: "X-Trace")
```

`HeaderName` contains the fixed Rust-recognized set and
`.other(String)` for extension fields. Matching is ASCII case-insensitive.
`HeaderValue` represents addresses, text, text lists, date-time values,
content type or disposition, structured `Received` data, and empty values.

Conveniences cover repeated address fields, resent and list headers, dates,
all `Received` fields, and the ID-bearing fields. Examples include
`messageIDs`, `inReplyToIDs`, `referenceIDs`, `resentMessageIDs`, `contentIDs`,
and `messageInstances`. `threadName` and `baseSubject` apply the Rust parser's
RFC-style reply/forward-prefix and mailing-list-tag removal. The standalone
equivalent is `ThreadNameParser.threadName(_:)`.

`AddressParser` is available independently of full-message parsing:

```swift
let parsed = AddressParser.parse(
    "Maintainers: Alice <alice@example.com>, Bob <bob@example.com>;"
)
let mailboxes = parsed?.flattened ?? []
```

It supports mailbox lists, groups, comments, obsolete forms, encoded display
names, and independently optional display names and addresses. It does not
require every parsed address-like value to contain `@`; callers that require
deliverable mailbox addresses must enforce that policy themselves.

`MailDateTime` preserves the parsed local components and original numeric
timezone offset, including its sign. It exposes `foundationDate`, `timestamp`,
`rfc3339`, and `rfc5322`, and can be parsed independently with
`parseRFC5322(_:)` or `parseRFC3339(_:)`.

`Received` exposes parsed hosts and IPs, reverse lookup, `by`, `for`, protocol,
TLS version and cipher, ID, ident, HELO and greeting, `via`, and its zoned
date.

## MIME and bodies

The MIME state machine handles mixed, alternative, related, digest, and
arbitrary multipart subtypes, including preambles, epilogues, malformed
boundaries, and ancestor-boundary recovery. It follows the Rust parser's body
classification and selection behavior for plain text, HTML, inline binary
parts, named parts, and explicit attachments.

`bodyText(at:)` and `bodyHTML(at:)` return the selected representation and
perform the same lazy text-to-HTML or HTML-to-text fallback as the Rust
library. `attachmentName(at:)` uses `Content-Disposition`'s `filename`
parameter first, then `Content-Type`'s `name` parameter. MIME parameters
include RFC 2231 continuations, language forms, and percent decoding.

Transfer decoding supports Base64 and quoted-printable. Failed decoding
rewinds to the appropriate raw content, sets `isEncodingProblem`, and uses the
same root or nested fallback classification as Rust. Header decoding supports
RFC 2047 B/Q encoded words and folded or malformed forms accepted by the
compatibility target.

Nested `message/rfc822`, `message/global`, and implicit `multipart/digest`
children are represented by `PartBody.message`. Recursively transfer-decoded
nested messages are limited to three levels. At the limit, the content is
retained as binary and marked as an encoding problem.

`bodyPreview(maxLength:)` follows the Rust preview behavior. `maxLength` is a
UTF-8 byte limit, Unicode scalars are not split, and HTML is converted to text
before previewing.

### HTML is not sanitized

An `.html` body preserves the decoded source markup. HTML-to-text conversion
implements the compatibility target's hidden-element, comment, whitespace,
line-break, malformed-tag, and entity behavior. Text-to-HTML conversion
escapes text and wraps it for display.

None of these operations sanitizes untrusted HTML. Applications that render
mail in a browser must apply an appropriate sanitizer and content-security
policy after parsing.

## Character sets and platforms

The library supports macOS and Linux and does not use Darwin-only HTML or
charset APIs. Rust's complete alias routing is implemented locally, including
its 45-byte label normalization and intentional Windows-1252 interpretation
of ASCII and ISO-8859-1 labels. UTF-7, UTF-16, replacement, x-user-defined,
and all 30 advertised single-byte families use local deterministic decoders.

The seven multibyte families (Big5, EUC-JP, EUC-KR, GB18030, GBK,
ISO-2022-JP, and Shift_JIS) use the pure-Swift
[Viceroy](https://github.com/gistya/viceroy) package. The dependency is pinned
to version 1.1.1 and only its Chinese, Japanese, and Korean package traits are
enabled. Static decoder dispatch makes a missing required trait a build-time
error. Unknown charset labels fall back to lossy UTF-8.

Valid-input decoding is platform-independent. The differential suite covers
1,726,049 candidate multibyte sequences and exactly matches all 1,209,322
Rust-defined valid results; the local single-byte suite checks all 7,680 byte
mappings. Representative malformed replacement behavior is also tested, but
is not a separately frozen compatibility guarantee.

Linux Foundation behavior is provided by
[swift-corelibs-foundation](https://github.com/swiftlang/swift-corelibs-foundation).
Compatibility outside the parser's verified Foundation paths is best-effort.

## Scope exclusions

`MailParser` intentionally does not provide:

- mbox or other mailbox-file parsing;
- runtime parser customization or header-parser registration;
- message construction, mutation, or generation.

It parses one owned RFC 5322 message at a time with a fixed compatibility
profile.

## Nexus integration boundary

The general-purpose library does not require a `Message-ID`. Nexus owns that
domain constraint in `IngestMessageParser`, which rejects an unparseable
message or a missing usable ID and applies the legacy LKML comment and
whitespace canonicalization to `Message-ID`, `In-Reply-To`, and `References`.

Nexus immediately projects the complete `Message` into its smaller
`IngestMailMessage` model. That projection selects the first text body with
HTML fallback, filters recipients to concrete `@` addresses, applies Nexus
fallbacks and alias handling, converts the zoned date to an absolute
Foundation `Date`, and then releases the raw MIME tree before database
batching. Nexus thread anchoring and persistence policy remain separate from
the library's RFC base-subject convenience.

## Upstream attribution

Substantially translated algorithms and tables retain SPDX attribution to
Stalwart Labs and are licensed under Apache-2.0 or MIT, matching
[mail-parser](https://github.com/stalwartlabs/mail-parser) 0.11.6 at commit
`b4366b7`.

The differential fixture corpus retains its original copyright and license
notices. See the local
[fixture attribution](../Tests/MailParserTests/Fixtures/RustMailParser/ATTRIBUTION.md)
and the `COPYING` files stored with the corresponding fixtures.

Viceroy remains an external dependency under the Mozilla Public License 2.0.
Its source and license are available in the
[Viceroy repository](https://github.com/gistya/viceroy).
