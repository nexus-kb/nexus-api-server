import Foundation

struct MailSearchFilter:
    Codable,
    Sendable,
    Equatable
{
    let text: String?
    let subject: String?
    let author: String?
    let sentAtLowerBound: Date?
    let sentAtUpperBound: Date?
}

enum MailSearchParseError:
    Error,
    CustomStringConvertible,
    Sendable
{
    case queryTooLong
    case unterminatedQuote
    case emptySelector(String)
    case duplicateSelector(String)
    case invalidSelectorValue(String)
    case invalidDate(String)
    case invalidDateRange(String)

    var description: String {
        switch self {
        case .queryTooLong:
            "Search query must not exceed 512 characters"
        case .unterminatedQuote:
            "Search query contains an unterminated quote"
        case .emptySelector(let selector):
            "\(selector): requires a value"
        case .duplicateSelector(let selector):
            "\(selector): may only appear once"
        case .invalidSelectorValue(let selector):
            "Invalid \(selector): selector value"
        case .invalidDate(let value):
            "Invalid search date: \(value)"
        case .invalidDateRange(let value):
            "Invalid search date range: \(value)"
        }
    }
}

enum MailSearchParser {
    static func parse(
        _ query: String?
    ) throws -> MailSearchFilter? {
        guard let query else {
            return nil
        }

        guard query.count <= 512 else {
            throw MailSearchParseError
                .queryTooLong
        }

        let characters = Array(query)
        var index = 0
        var textTokens: [String] = []
        var subject: String?
        var author: String?
        var dateValue: String?

        while index < characters.count {
            while index < characters.count,
                  characters[index].isWhitespace
            {
                index += 1
            }

            guard index < characters.count else {
                break
            }

            if matches(
                "subject:",
                in: characters,
                at: index
            ) {
                guard subject == nil else {
                    throw MailSearchParseError
                        .duplicateSelector("subject")
                }

                index += "subject:".count
                subject = try selectorValue(
                    named: "subject",
                    in: characters,
                    at: &index,
                    preservingQuotes: true
                )
                continue
            }

            if matches(
                "author:",
                in: characters,
                at: index
            ) {
                guard author == nil else {
                    throw MailSearchParseError
                        .duplicateSelector("author")
                }

                index += "author:".count
                author = try selectorValue(
                    named: "author",
                    in: characters,
                    at: &index
                )
                continue
            }

            if matches(
                "date:",
                in: characters,
                at: index
            ) {
                guard dateValue == nil else {
                    throw MailSearchParseError
                        .duplicateSelector("date")
                }

                index += "date:".count
                dateValue = try selectorValue(
                    named: "date",
                    in: characters,
                    at: &index
                )
                continue
            }

            textTokens.append(
                try searchToken(
                    in: characters,
                    at: &index
                )
            )
        }

        let text = textTokens
            .joined(separator: " ")
            .nilIfEmpty
        let normalizedAuthor = author?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .nilIfEmpty

        if author != nil,
           normalizedAuthor == nil
        {
            throw MailSearchParseError
                .emptySelector("author")
        }

        let bounds = try dateValue.map(
            dateBounds
        )

        guard text != nil
                || subject != nil
                || normalizedAuthor != nil
                || bounds != nil
        else {
            return nil
        }

        return MailSearchFilter(
            text: text,
            subject: subject,
            author: normalizedAuthor,
            sentAtLowerBound: bounds?.lower,
            sentAtUpperBound: bounds?.upper
        )
    }

    private static func matches(
        _ value: String,
        in characters: [Character],
        at index: Int
    ) -> Bool {
        let end = index + value.count

        guard end <= characters.count else {
            return false
        }

        return String(characters[index..<end])
            .lowercased() == value
    }

    private static func selectorValue(
        named selector: String,
        in characters: [Character],
        at index: inout Int,
        preservingQuotes: Bool = false
    ) throws -> String {
        guard index < characters.count,
              !characters[index].isWhitespace
        else {
            throw MailSearchParseError
                .emptySelector(selector)
        }

        if characters[index] == "\"" {
            index += 1
            var value = ""
            var escaping = false

            while index < characters.count {
                let character = characters[index]
                index += 1

                if escaping {
                    value.append(character)
                    escaping = false
                } else if character == "\\" {
                    escaping = true
                } else if character == "\"" {
                    guard index == characters.count
                            || characters[index]
                                .isWhitespace
                    else {
                        throw MailSearchParseError
                            .invalidSelectorValue(
                                selector
                            )
                    }

                    guard !value.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty else {
                        throw MailSearchParseError
                            .emptySelector(selector)
                    }

                    guard preservingQuotes else {
                        return value
                    }

                    let escaped = value
                        .replacingOccurrences(
                            of: "\\",
                            with: "\\\\"
                        )
                        .replacingOccurrences(
                            of: "\"",
                            with: "\\\""
                        )
                    return "\"\(escaped)\""
                } else {
                    value.append(character)
                }
            }

            throw MailSearchParseError
                .unterminatedQuote
        }

        let start = index

        while index < characters.count,
              !characters[index].isWhitespace
        {
            index += 1
        }

        let value = String(
            characters[start..<index]
        )

        guard !value.isEmpty else {
            throw MailSearchParseError
                .emptySelector(selector)
        }

        return value
    }

    private static func searchToken(
        in characters: [Character],
        at index: inout Int
    ) throws -> String {
        let start = index
        var quoted = false
        var escaping = false

        while index < characters.count,
              quoted
                || !characters[index].isWhitespace
        {
            let character = characters[index]

            if escaping {
                escaping = false
            } else if quoted,
                      character == "\\"
            {
                escaping = true
            } else if character == "\"" {
                quoted.toggle()
            }

            index += 1
        }

        guard !quoted else {
            throw MailSearchParseError
                .unterminatedQuote
        }

        return String(characters[start..<index])
    }

    private static func dateBounds(
        _ value: String
    ) throws -> (
        lower: Date?,
        upper: Date?
    ) {
        let components = value.components(
            separatedBy: ".."
        )

        if components.count == 1 {
            let lower = try date(
                components[0]
            )
            let upper = try dayAfter(
                lower,
                originalValue: value
            )
            return (lower, upper)
        }

        guard components.count == 2,
              !components[0].isEmpty
                || !components[1].isEmpty
        else {
            throw MailSearchParseError
                .invalidDateRange(value)
        }

        let lower = try components[0]
            .nilIfEmpty
            .map(date)
        let upper = try components[1]
            .nilIfEmpty
            .map {
                try dayAfter(
                    date($0),
                    originalValue: value
                )
            }

        if let lower,
           let upper,
           lower >= upper
        {
            throw MailSearchParseError
                .invalidDateRange(value)
        }

        return (lower, upper)
    }

    private static func date(
        _ value: String
    ) throws -> Date {
        let components = value.split(
            separator: "-",
            omittingEmptySubsequences: false
        )

        guard components.count == 3,
              components[0].count == 4,
              components[1].count == 2,
              components[2].count == 2,
              let year = Int(components[0]),
              let month = Int(components[1]),
              let day = Int(components[2])
        else {
            throw MailSearchParseError
                .invalidDate(value)
        }

        var calendar = Calendar(
            identifier: .gregorian
        )
        calendar.timeZone = TimeZone(
            secondsFromGMT: 0
        )!

        let requested = DateComponents(
            year: year,
            month: month,
            day: day
        )

        guard let date = calendar.date(
            from: requested
        ) else {
            throw MailSearchParseError
                .invalidDate(value)
        }

        let resolved = calendar.dateComponents(
            [.year, .month, .day],
            from: date
        )

        guard resolved.year == year,
              resolved.month == month,
              resolved.day == day
        else {
            throw MailSearchParseError
                .invalidDate(value)
        }

        return date
    }

    private static func dayAfter(
        _ date: Date,
        originalValue: String
    ) throws -> Date {
        var calendar = Calendar(
            identifier: .gregorian
        )
        calendar.timeZone = TimeZone(
            secondsFromGMT: 0
        )!

        guard let value = calendar.date(
            byAdding: .day,
            value: 1,
            to: date
        ) else {
            throw MailSearchParseError
                .invalidDate(originalValue)
        }

        return value
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
