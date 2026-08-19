/*
 * SPDX-FileCopyrightText: 2020 Stalwart Labs LLC <hello@stalw.art>
 *
 * SPDX-License-Identifier: Apache-2.0 OR MIT
 *
 * Charset alias routing and the UTF-7/UTF-16 decoders are substantially
 * derived from mail-parser 0.11.6.
 */

import Foundation
import Viceroy

/// Charset decoding used for MIME bodies, RFC 2047 words, and RFC 2231 values.
enum CharsetDecoder {
    static func decode<C: Collection>(
        _ bytes: C,
        charset: String?
    ) -> String where C.Element == UInt8 {
        decode(Data(bytes), charset: charset)
    }

    static func decode(_ data: Data, charset: String?) -> String {
        guard let charset else { return lossyUTF8(data) }
        let normalized = normalize(charset)

        switch decoder(for: normalized) {
        case .none, .utf8:
            return lossyUTF8(data)
        case .singleByte(let table):
            return decodeSingleByte(data, table: table)
        case .viceroy(let encoding):
            return decodeWithViceroy(data, encoding: encoding)
        case .utf7:
            return decodeUTF7(data)
        case .utf16:
            return decodeUTF16(data, byteOrder: nil)
        case .utf16BigEndian:
            return decodeUTF16(data, byteOrder: .bigEndian)
        case .utf16LittleEndian:
            return decodeUTF16(data, byteOrder: .littleEndian)
        case .replacement:
            return data.isEmpty ? "" : "\u{FFFD}"
        case .userDefined:
            return decodeUserDefined(data)
        }
    }

    /// Whether a label is one of mail-parser's explicitly recognized aliases.
    /// UTF-8 aliases intentionally return false in Rust and use UTF-8 fallback.
    static func recognizes(_ charset: String) -> Bool {
        guard let decoder = decoder(for: normalize(charset)) else { return false }
        return decoder != .utf8
    }

    private static func normalize(_ charset: String) -> String {
        let trimmed = charset.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = trimmed.utf8.prefix(45).map { byte -> UInt8 in
            switch byte {
            case 65...90: byte + 32
            case 45: 95
            default: byte
            }
        }
        return String(decoding: prefix, as: UTF8.self)
    }

    private static func decoder(for charset: String) -> Decoder? {
        switch charset {
        case "utf8", "utf_8", "unicode11utf8", "unicode20utf8",
             "x_unicode20utf8", "unicode_1_1_utf_8", "":
            return .utf8

        case "ansi_x3.4_1968", "ascii", "cp1252", "cp819", "csisolatin1",
             "cswindows1252", "ibm819", "iso88591", "iso8859_1",
             "iso_8859_1", "iso_8859_1:1987", "iso_ir_100", "l1",
             "latin1", "us_ascii", "windows_1252", "x_cp1252":
            return .singleByte(.cp1252)

        case "cp1250", "cswindows1250", "windows_1250", "x_cp1250":
            return .singleByte(.cp1250)
        case "cp1251", "cswindows1251", "windows_1251", "x_cp1251":
            return .singleByte(.cp1251)
        case "cp1253", "cswindows1253", "windows_1253", "x_cp1253":
            return .singleByte(.cp1253)
        case "cp1254", "cswindows1254", "windows_1254", "x_cp1254":
            return .singleByte(.cp1254)
        case "cp1255", "cswindows1255", "windows_1255", "x_cp1255":
            return .singleByte(.cp1255)
        case "cp1256", "cswindows1256", "windows_1256", "x_cp1256":
            return .singleByte(.cp1256)
        case "cp1257", "cswindows1257", "windows_1257", "x_cp1257":
            return .singleByte(.cp1257)
        case "cp1258", "cswindows1258", "windows_1258", "x_cp1258":
            return .singleByte(.cp1258)

        case "csisolatin2", "iso88592", "iso8859_2", "iso_8859_2",
             "iso_8859_2:1987", "iso_ir_101", "l2", "latin2":
            return .singleByte(.iso8859_2)
        case "csisolatin3", "iso88593", "iso8859_3", "iso_8859_3",
             "iso_8859_3:1988", "iso_ir_109", "l3", "latin3":
            return .singleByte(.iso8859_3)
        case "csisolatin4", "iso88594", "iso8859_4", "iso_8859_4",
             "iso_8859_4:1988", "iso_ir_110", "l4", "latin4":
            return .singleByte(.iso8859_4)
        case "csisolatincyrillic", "cyrillic", "iso88595", "iso8859_5",
             "iso_8859_5", "iso_8859_5:1988", "iso_ir_144":
            return .singleByte(.iso8859_5)
        case "arabic", "asmo_708", "csiso88596e", "csiso88596i",
             "csisolatinarabic", "ecma_114", "iso88596", "iso8859_6",
             "iso_8859_6", "iso_8859_6:1987", "iso_8859_6_e",
             "iso_8859_6_i", "iso_ir_127":
            return .singleByte(.iso8859_6)
        case "csisolatingreek", "ecma_118", "elot_928", "greek", "greek8",
             "iso88597", "iso8859_7", "iso_8859_7", "iso_8859_7:1987",
             "iso_ir_126", "sun_eu_greek":
            return .singleByte(.iso8859_7)
        case "csiso88598e", "csiso88598i", "csisolatinhebrew", "hebrew",
             "iso88598", "iso8859_8", "iso_8859_8", "iso_8859_8:1988",
             "iso_8859_8_e", "iso_8859_8_i", "iso_ir_138", "logical",
             "visual":
            return .singleByte(.iso8859_8)
        case "csisolatin5", "iso88599", "iso8859_9", "iso_8859_9",
             "iso_8859_9:1989", "iso_ir_148", "l5", "latin5":
            return .singleByte(.iso8859_9)
        case "csisolatin6", "iso885910", "iso8859_10", "iso_8859_10",
             "iso_8859_10:1992", "iso_ir_157", "l6", "latin6":
            return .singleByte(.iso8859_10)
        case "cstis620", "iso885911", "iso8859_11", "iso_8859_11", "tis_620":
            return .singleByte(.tis620)
        case "csiso885913", "iso885913", "iso8859_13", "iso_8859_13":
            return .singleByte(.iso8859_13)
        case "csiso885914", "iso885914", "iso8859_14", "iso_8859_14",
             "iso_8859_14:1998", "iso_celtic", "iso_ir_199", "l8", "latin8":
            return .singleByte(.iso8859_14)
        case "csiso885915", "csisolatin9", "iso885915", "iso8859_15",
             "iso_8859_15", "l9", "latin_9":
            return .singleByte(.iso8859_15)
        case "csiso885916", "iso_8859_16", "iso_8859_16:2001", "iso_ir_226",
             "l10", "latin10":
            return .singleByte(.iso8859_16)

        case "850", "cp850", "cspc850multilingual", "ibm850":
            return .singleByte(.ibm850)
        case "866", "cp866", "csibm866", "ibm866":
            return .singleByte(.ibm866)
        case "cskoi8r", "koi", "koi8", "koi8_r":
            return .singleByte(.koi8R)
        case "cskoi8u", "koi8_ru", "koi8_u":
            return .singleByte(.koi8U)
        case "csmacintosh", "mac", "macintosh", "x_mac_roman":
            return .singleByte(.macintosh)
        case "x_mac_cyrillic", "x_mac_ukrainian":
            return .singleByte(.macCyrillic)
        case "cswindows874", "dos_874", "windows_874":
            return .singleByte(.windows874)

        case "big5", "big5_hkscs", "cn_big5", "csbig5", "x_x_big5":
            return .viceroy(.big5)
        case "cseucpkdfmtjapanese", "euc_jp",
             "extended_unix_code_packed_format_for_japanese", "x_euc_jp":
            return .viceroy(.eucJP)
        case "cseuckr", "csksc56011987", "euc_kr", "iso_ir_149", "korean",
             "ks_c_5601_1987", "ks_c_5601_1989", "ksc5601", "ksc_5601",
             "windows_949":
            return .viceroy(.eucKR)
        case "csgb18030", "gb18030", "gb2312":
            return .viceroy(.gb18030)
        case "chinese", "cp936", "csgb2312", "csgbk", "csiso58gb231280",
             "gb_2312", "gb_2312_80", "gbk", "iso_ir_58", "ms936",
             "windows_936", "x_gbk":
            return .viceroy(.gbk)
        case "csiso2022jp", "iso_2022_jp":
            return .viceroy(.iso2022JP)
        case "csshiftjis", "ms932", "ms_kanji", "shift_jis", "sjis",
             "windows_31j", "x_sjis":
            return .viceroy(.shiftJIS)

        case "csunicode", "csutf16", "iso_10646_ucs_2", "ucs_2", "unicode",
             "unicodefeff", "utf_16":
            return .utf16
        case "csutf16be", "unicodefffe", "utf_16be":
            return .utf16BigEndian
        case "csutf16le", "utf_16le":
            return .utf16LittleEndian
        case "csutf7", "utf_7":
            return .utf7
        case "csiso2022kr", "hz_gb_2312", "iso_2022_cn", "iso_2022_cn_ext",
             "iso_2022_kr", "replacement":
            return .replacement
        case "x_user_defined":
            return .userDefined
        default:
            return nil
        }
    }

    private static func lossyUTF8(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    private static func decodeSingleByte(
        _ data: Data,
        table: SingleByteCharsetTable
    ) -> String {
        var result = String()
        result.reserveCapacity(data.count * 2)
        for byte in data {
            result.unicodeScalars.append(table.scalar(for: byte))
        }
        return result
    }

    private static func decodeWithViceroy(
        _ data: Data,
        encoding: ViceroyDecoder
    ) -> String {
        let bytes = [UInt8](data)
        let decoded: String?
        switch encoding {
        case .big5:
            decoded = try? Viceroy.Encoding.Big5.decode(bytes, mode: .replacement)
        case .eucJP:
            decoded = try? Viceroy.Encoding.EUCJP.decode(bytes, mode: .replacement)
        case .eucKR:
            decoded = try? Viceroy.Encoding.EUCKR.decode(bytes, mode: .replacement)
        case .gb18030:
            decoded = try? Viceroy.Encoding.GB18030.decode(bytes, mode: .replacement)
        case .gbk:
            decoded = try? Viceroy.Encoding.GBK.decode(bytes, mode: .replacement)
        case .iso2022JP:
            decoded = try? Viceroy.Encoding.ISO2022JP.decode(bytes, mode: .replacement)
        case .shiftJIS:
            decoded = try? Viceroy.Encoding.ShiftJIS.decode(bytes, mode: .replacement)
        }
        return decoded ?? lossyUTF8(data)
    }

    private static func decodeUTF16(
        _ data: Data,
        byteOrder requestedByteOrder: ByteOrder?
    ) -> String {
        let bytes = [UInt8](data)
        var index = 0
        let byteOrder: ByteOrder
        if let requestedByteOrder {
            byteOrder = requestedByteOrder
        } else if bytes.count >= 2, bytes[0] == 0xFE, bytes[1] == 0xFF {
            byteOrder = .bigEndian
            index = 2
        } else if bytes.count >= 2, bytes[0] == 0xFF, bytes[1] == 0xFE {
            byteOrder = .littleEndian
            index = 2
        } else {
            byteOrder = .littleEndian
        }

        var codeUnits: [UInt16] = []
        codeUnits.reserveCapacity((bytes.count - index) / 2)
        while index + 1 < bytes.count {
            let value: UInt16
            switch byteOrder {
            case .bigEndian:
                value = UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1])
            case .littleEndian:
                value = UInt16(bytes[index + 1]) << 8 | UInt16(bytes[index])
            }
            codeUnits.append(value)
            index += 2
        }
        return String(decoding: codeUnits, as: UTF16.self)
    }

    private static func decodeUTF7(_ data: Data) -> String {
        let bytes = [UInt8](data)
        var result = String()
        result.reserveCapacity(bytes.count)
        var index = 0

        while index < bytes.count {
            guard bytes[index] == 0x2B else {
                result.unicodeScalars.append(UnicodeScalar(UInt32(bytes[index]))!)
                index += 1
                continue
            }

            index += 1
            var sextets: [UInt8] = []
            var decodedBytes: [UInt8] = []
            var terminator: UInt8?
            while index < bytes.count {
                if let value = TransferDecoder.base64Value(bytes[index]) {
                    sextets.append(value)
                    if sextets.count == 4 {
                        decodedBytes.append((sextets[0] << 2) | (sextets[1] >> 4))
                        decodedBytes.append((sextets[1] << 4) | (sextets[2] >> 2))
                        decodedBytes.append((sextets[2] << 6) | sextets[3])
                        sextets.removeAll(keepingCapacity: true)
                    }
                    index += 1
                } else {
                    terminator = bytes[index]
                    index += 1
                    break
                }
            }

            if terminator != nil {
                switch sextets.count {
                case 1:
                    decodedBytes.append(sextets[0] << 2)
                case 2:
                    decodedBytes.append((sextets[0] << 2) | (sextets[1] >> 4))
                case 3:
                    decodedBytes.append((sextets[0] << 2) | (sextets[1] >> 4))
                    decodedBytes.append((sextets[1] << 4) | (sextets[2] >> 2))
                default:
                    break
                }

                let completeByteCount = decodedBytes.count & ~1
                if completeByteCount > 0 {
                    result += decodeUTF16(
                        Data(decodedBytes.prefix(completeByteCount)),
                        byteOrder: .bigEndian
                    )
                } else if !decodedBytes.isEmpty {
                    result.append("\u{FFFD}")
                } else {
                    result.append("+")
                    if let terminator {
                        result.unicodeScalars.append(UnicodeScalar(UInt32(terminator))!)
                    }
                }
            }
        }
        return result
    }

    private static func decodeUserDefined(_ data: Data) -> String {
        var result = String()
        result.reserveCapacity(data.count * 2)
        for byte in data {
            let scalar = byte < 0x80
                ? UInt32(byte)
                : 0xF780 + UInt32(byte - 0x80)
            result.unicodeScalars.append(UnicodeScalar(scalar)!)
        }
        return result
    }
}

private enum Decoder: Equatable {
    case utf8
    case singleByte(SingleByteCharsetTable)
    case viceroy(ViceroyDecoder)
    case utf7
    case utf16
    case utf16BigEndian
    case utf16LittleEndian
    case replacement
    case userDefined
}

private enum ViceroyDecoder: Equatable {
    case big5
    case eucJP
    case eucKR
    case gb18030
    case gbk
    case iso2022JP
    case shiftJIS
}

private enum ByteOrder {
    case bigEndian
    case littleEndian
}
