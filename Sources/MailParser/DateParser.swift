/*
 * SPDX-FileCopyrightText: 2020 Stalwart Labs LLC <hello@stalw.art>
 *
 * SPDX-License-Identifier: Apache-2.0 OR MIT
 */

import Foundation

enum MailDateParser {
    static func parse(_ source: String) -> MailDateTime? {
        let bytes = Array(source.utf8)
        var position = 0
        var parts = Array(repeating: 0, count: 7)
        var remainingDigits = [2, 2, 4, 2, 2, 2, 4]
        var monthToken: [UInt8] = []

        var isPositive = true
        var isNewToken = true
        var ignoreToken = true
        var commentDepth = 0
        var index = 0

        func normalized(_ byte: UInt8) -> UInt8 {
            (65...90).contains(byte) ? byte + 32 : byte
        }

        while index < bytes.count {
            let byte = bytes[index]
            var nextPart = false

            if byte == 10 {
                var next = index + 1
                if next < bytes.count, bytes[next] == 32 || bytes[next] == 9 {
                    while next < bytes.count, bytes[next] == 32 || bytes[next] == 9 {
                        next += 1
                    }
                    if !isNewToken && !ignoreToken && commentDepth == 0 {
                        nextPart = true
                    } else {
                        index = next
                        continue
                    }
                } else {
                    break
                }
            } else if commentDepth > 0 {
                if byte == 41 {
                    commentDepth -= 1
                } else if byte == 40 {
                    commentDepth += 1
                } else if byte == 92, index + 1 < bytes.count, bytes[index + 1] == 41 {
                    index += 1
                }
                index += 1
                continue
            } else {
                switch byte {
                case 48...57:
                    if position < parts.count, remainingDigits[position] > 0 {
                        remainingDigits[position] -= 1
                        parts[position] += Int(byte - 48)
                            * integerPowerOfTen(remainingDigits[position])
                        ignoreToken = false
                    }
                    isNewToken = false

                case 58 where !isNewToken && !ignoreToken
                    && (position == 3 || position == 4):
                    nextPart = true

                case 43:
                    position = 6

                case 45:
                    isPositive = false
                    position = 6

                case 32 where !isNewToken && !ignoreToken,
                     9 where !isNewToken && !ignoreToken:
                    nextPart = true

                case 65...90, 97...122:
                    if position == 1, monthToken.count < 3 {
                        monthToken.append(normalized(byte))
                    }
                    if position == 6 {
                        var zone = [normalized(byte)]
                        var next = index + 1
                        while next < bytes.count,
                              zone.count < 3,
                              (65...90).contains(bytes[next])
                                || (97...122).contains(bytes[next])
                        {
                            zone.append(normalized(bytes[next]))
                            next += 1
                        }
                        let offset = obsoleteZone[String(decoding: zone, as: UTF8.self)] ?? 0
                        isPositive = offset >= 0
                        parts[6] = abs(offset) * 100
                        remainingDigits[6] = 0
                        nextPart = true
                        index = max(index, next - 1)
                    }
                    isNewToken = false

                case 40:
                    commentDepth += 1
                    isNewToken = true
                    index += 1
                    continue

                case 44, 13:
                    break

                case 59:
                    position = 0
                    parts = Array(repeating: 0, count: 7)
                    remainingDigits = [2, 2, 4, 2, 2, 2, 4]
                    monthToken.removeAll(keepingCapacity: true)
                    isPositive = true
                    isNewToken = true
                    ignoreToken = true
                    index += 1
                    continue

                default:
                    break
                }
            }

            if nextPart {
                if position < parts.count, remainingDigits[position] > 0 {
                    parts[position] /= integerPowerOfTen(remainingDigits[position])
                }
                position += 1
                isNewToken = true
            }
            index += 1
        }

        guard position >= 6 else {
            return nil
        }

        let month: Int
        if monthToken.count == 3 {
            month = months[String(decoding: monthToken, as: UTF8.self)] ?? 0
        } else {
            month = parts[1]
        }
        guard (1...12).contains(month) else {
            return nil
        }

        let parsedYear: Int
        switch parts[2] {
        case 0...49:
            parsedYear = parts[2] + 2000
        case 50...99:
            parsedYear = parts[2] + 1900
        default:
            parsedYear = parts[2]
        }

        return MailDateTime(
            year: parsedYear,
            month: month,
            day: parts[0],
            hour: parts[3],
            minute: parts[4],
            second: parts[5],
            isNegativeOffset: !isPositive,
            offsetHour: (parts[6] / 100) % 24,
            offsetMinute: (parts[6] % 100) % 60
        )
    }

    static func parseRFC3339(_ source: String) -> MailDateTime? {
        let bytes = Array(source.utf8)
        var position = 0
        var parts = Array(repeating: 0, count: 8)
        var remainingDigits = [4, 2, 2, 2, 2, 2, 2, 2]
        var skipDigits = false
        var isPositive = true

        for byte in bytes {
            switch byte {
            case 48...57 where !skipDigits:
                guard position < parts.count, remainingDigits[position] > 0 else {
                    return nil
                }
                remainingDigits[position] -= 1
                parts[position] += Int(byte - 48)
                    * integerPowerOfTen(remainingDigits[position])

            case 45:
                if position <= 1 {
                    position += 1
                } else if position == 5 {
                    position += 1
                    isPositive = false
                    skipDigits = false
                } else {
                    return nil
                }

            case 84 where position == 2:
                position += 1

            case 58 where position == 3 || position == 4 || position == 6:
                position += 1

            case 43 where position == 5:
                position += 1
                skipDigits = false

            case 46 where position == 5:
                skipDigits = true

            default:
                break
            }
        }

        guard position >= 5 else {
            return nil
        }
        return MailDateTime(
            year: parts[0],
            month: parts[1],
            day: parts[2],
            hour: parts[3],
            minute: parts[4],
            second: parts[5],
            isNegativeOffset: !isPositive,
            offsetHour: parts[6],
            offsetMinute: parts[7]
        )
    }

    private static let months: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
    ]

    private static let obsoleteZone: [String: Int] = [
        "edt": -4, "est": -5, "cdt": -5, "cst": -6,
        "mdt": -6, "mst": -7, "pdt": -7, "pst": -8,
    ]
}

public extension MailDateTime {
    static func parseRFC5322(_ value: String) -> MailDateTime? {
        MailDateParser.parse(value)
    }

    static func parseRFC3339(_ value: String) -> MailDateTime? {
        MailDateParser.parseRFC3339(value)
    }

    var isValid: Bool {
        (1900...3000).contains(year)
            && (1...12).contains(month)
            && (1...31).contains(day)
            && (0...23).contains(hour)
            && (0...59).contains(minute)
            && (0...59).contains(second)
            && (0...23).contains(offsetHour)
            && (0...59).contains(offsetMinute)
    }

    var exactTimestamp: Int64 {
        guard isValid else {
            return 0
        }
        return localTimestamp + Int64(offsetHour * 3_600 + offsetMinute * 60)
            * (isNegativeOffset ? 1 : -1)
    }

    var localTimestamp: Int64 {
        guard isValid else {
            return 0
        }
        let monthValue = UInt32(month)
        let yearBase: Int64 = 4_800
        let adjustedMonth = monthValue &- 3
        let carry: Int64 = adjustedMonth > monthValue ? 1 : 0
        let adjust: UInt32 = carry > 0 ? 12 : 0
        let adjustedYear = Int64(year) + yearBase - carry
        let monthDays = ((adjustedMonth &+ adjust) * 62_719 + 769) / 2_048
        let leapDays = adjustedYear / 4 - adjustedYear / 100 + adjustedYear / 400

        return (
            adjustedYear * 365
                + leapDays
                + Int64(monthDays)
                + Int64(day - 1)
                - 2_472_632
        ) * 86_400
            + Int64(hour * 3_600 + minute * 60 + second)
    }

    var rfc5322: String {
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let monthNames = [
            "Jan", "Feb", "Mar", "Apr", "May", "Jun",
            "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
        ]
        let monthName = (1...12).contains(month) ? monthNames[month - 1] : ""
        return String(
            format: "%@, %d %@ %04d %02d:%02d:%02d %@%02d%02d",
            dayNames[dayOfWeek], day, monthName, year, hour, minute, second,
            isNegativeOffset && (offsetHour != 0 || offsetMinute != 0) ? "-" : "+",
            offsetHour, offsetMinute
        )
    }

    var dayOfWeek: Int {
        Int((Int64(floor(Double(localTimestamp) / 86_400.0)) + 4).positiveModulo(7))
    }

    var julianDay: Int64 {
        guard isValid else {
            return 0
        }
        let adjustedMonth: Int
        let adjustedYear: Int
        if month > 2 {
            adjustedMonth = month - 3
            adjustedYear = year
        } else {
            adjustedMonth = month + 9
            adjustedYear = year - 1
        }
        let century = adjustedYear / 100
        return Int64(
            century * 146_097 / 4
                + (adjustedYear - century * 100) * 1_461 / 4
                + (adjustedMonth * 153 + 2) / 5
                + day
                + 1_721_119
        )
    }

    static func fromTimestamp(_ timestamp: Int64) -> MailDateTime {
        let z = timestamp.floorDivided(by: 86_400) + 719_468
        let seconds = timestamp.positiveModulo(86_400)
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = UInt64(z - era * 146_097)
        let yearOfEra = (
            dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096
        ) / 365
        let rawYear = Int64(yearOfEra) + era * 400
        let dayOfYear = dayOfEra
            - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthPart = (5 * dayOfYear + 2) / 153
        let parsedDay = dayOfYear - (153 * monthPart + 2) / 5 + 1
        let parsedMonth = monthPart < 10 ? monthPart + 3 : monthPart - 9

        return MailDateTime(
            year: Int(rawYear + (parsedMonth <= 2 ? 1 : 0)),
            month: Int(parsedMonth),
            day: Int(parsedDay),
            hour: Int(seconds / 3_600),
            minute: Int((seconds / 60) % 60),
            second: Int(seconds % 60),
            isNegativeOffset: false,
            offsetHour: 0,
            offsetMinute: 0
        )
    }

    func converted(toOffset offsetSeconds: Int64) -> MailDateTime? {
        let maximumOffset = Int64(23 * 3_600 + 59 * 60)
        guard isValid, (-maximumOffset...maximumOffset).contains(offsetSeconds) else {
            return nil
        }
        let (convertedTimestamp, overflow) = exactTimestamp.addingReportingOverflow(offsetSeconds)
        guard !overflow else {
            return nil
        }

        var value = MailDateTime.fromTimestamp(convertedTimestamp)
        let absoluteOffset = offsetSeconds.magnitude
        value = MailDateTime(
            year: value.year,
            month: value.month,
            day: value.day,
            hour: value.hour,
            minute: value.minute,
            second: value.second,
            isNegativeOffset: offsetSeconds < 0,
            offsetHour: Int(absoluteOffset / 3_600),
            offsetMinute: Int((absoluteOffset % 3_600) / 60)
        )
        return value
    }
}

private func integerPowerOfTen(_ exponent: Int) -> Int {
    guard exponent > 0 else {
        return 1
    }
    return (0..<exponent).reduce(1) { value, _ in value * 10 }
}

private extension Int64 {
    func positiveModulo(_ divisor: Int64) -> Int64 {
        let remainder = self % divisor
        return remainder >= 0 ? remainder : remainder + divisor
    }

    func floorDivided(by divisor: Int64) -> Int64 {
        let quotient = self / divisor
        let remainder = self % divisor
        return remainder < 0 ? quotient - 1 : quotient
    }
}
