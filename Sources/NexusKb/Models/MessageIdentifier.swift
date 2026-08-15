import Foundation

enum MessageIdentifierError: Error, Sendable {
    case invalid
}

struct MessageIdentifier:
    Sendable,
    Equatable,
    Hashable
{
    let value: String

    init(_ rawValue: String) throws {
        var value = rawValue

        if value.hasPrefix("<"),
           value.hasSuffix(">")
        {
            value.removeFirst()
            value.removeLast()
        }

        guard !value.isEmpty,
              !value.contains(where: \.isWhitespace),
              !value.contains("<"),
              !value.contains(">")
        else {
            throw MessageIdentifierError.invalid
        }

        self.value = value
    }
}
