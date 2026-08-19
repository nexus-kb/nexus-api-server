//
// SPDX-License-Identifier: Apache-2.0 OR MIT
//

import Foundation

/// A fixed, best-effort RFC 5322 and MIME message parser.
///
/// Parsing is intentionally nonthrowing. Malformed bodies are retained in
/// message parts and described by ``MessagePart/isEncodingProblem``. A `nil`
/// result means that no usable header block or message entity was found.
public struct MessageParser: Sendable {
    public init() {}

    public func parse(_ data: Data) -> Message? {
        StreamingMIMEParser(rawMessage: data).parse(skipBody: false)
    }

    public func parse<C: Collection>(_ bytes: C) -> Message?
    where C.Element == UInt8 {
        parse(Data(bytes))
    }

    public func parseHeaders(_ data: Data) -> Message? {
        StreamingMIMEParser(rawMessage: data).parse(skipBody: true)
    }

    public func parseHeaders<C: Collection>(_ bytes: C) -> Message?
    where C.Element == UInt8 {
        parseHeaders(Data(bytes))
    }
}
