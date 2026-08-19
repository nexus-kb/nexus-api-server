/*
 * SPDX-FileCopyrightText: 2020 Stalwart Labs LLC <hello@stalw.art>
 *
 * SPDX-License-Identifier: Apache-2.0 OR MIT
 *
 * Expected values are derived from mail-parser 0.11.6's decoder fixtures.
 */

import Foundation
import Testing
@testable import MailParser

@Test
func base64MatchesMailParserRecoveryRules() {
    let folded = Data("w 6 H D q c O t w 7 P D u g==".utf8)
    let decoded = TransferDecoder.decodeBase64(folded)

    #expect(decoded.map { String(decoding: $0, as: UTF8.self) } == "áéíóú")
    #expect(TransferDecoder.decodeBase64(Data("TQ".utf8)) == Data())
    #expect(TransferDecoder.decodeBase64(Data("VGVzdA===".utf8)) == Data("Test".utf8))
    #expect(TransferDecoder.decodeBase64(Data("VGVzdA%=".utf8)) == nil)
}

@Test
func quotedPrintableSupportsStrictAndMIMERecoveryModes() {
    let source = Data("hello  \r\nbar=\r\nbaz=E2=80=94".utf8)
    let strict = TransferDecoder.decodeQuotedPrintable(source)

    #expect(strict.map { String(decoding: $0, as: UTF8.self) } == "hello\r\nbarbaz—")
    #expect(TransferDecoder.decodeQuotedPrintable(Data("bad=QZ".utf8)) == nil)
    #expect(
        TransferDecoder.decodeQuotedPrintableMIME(Data("bad=QZ".utf8))
            == Data("bad=QZ".utf8)
    )
    #expect(TransferDecoder.decodeQuotedPrintableMIME(Data("bad==20".utf8)) == nil)
}

@Test
func percentDecoderIsStrictForRFC2231Values() {
    #expect(
        TransferDecoder.decodePercentEncoded(Data("r%C3%A9sum%C3%A9.pdf".utf8))
            == Data("résumé.pdf".utf8)
    )
    #expect(TransferDecoder.decodePercentEncoded(Data("bad%2".utf8)) == nil)
    #expect(TransferDecoder.decodePercentEncoded(Data("bad%XZ".utf8)) == nil)
}

@Test
func rfc2047DecodesAdjacentWordsCharsetsAndLanguageSuffixes() {
    let source = "prefix =?ISO-8859-1?Q?Olle_J=E4rnefors?= \r\n\t"
        + "=?utf-8*unknown?B?4pi6?= suffix"

    #expect(RFC2047Decoder.decodeWords(source) == "prefix Olle Järnefors☺ suffix")
    #expect(
        RFC2047Decoder.decodeWords("=?iso-8859-1?Q?=805.4bn?=")
            == "€5.4bn"
    )
}

@Test
func rfc2047LeavesMalformedWordsUnchanged() {
    let malformedBase64 = "=?UTF-8?B?4pi6\n?="
    let malformedQuotedPrintable = "=?UTF-8?Q?bad=XX?="

    #expect(RFC2047Decoder.decodeWords(malformedBase64) == malformedBase64)
    #expect(RFC2047Decoder.decodeWords(malformedQuotedPrintable) == malformedQuotedPrintable)
}

@Test
func charsetAliasesAndSingleByteFamiliesMatchMailParser() {
    let cases: [(String, Data, String)] = [
        ("ansi_x3.4-1968", Data([0x80, 0x35, 0x2E, 0x34]), "€5.4"),
        (
            "iso8859-5",
            Data([0xBF, 0xE0, 0xD8, 0xD2, 0xD5, 0xE2]),
            "Привет"
        ),
        (
            "cswindows1250",
            Data([0x73, 0x6C, 0x61, 0x9A, 0xE8, 0x69, 0xE8, 0x61, 0x72, 0x6E, 0x6F]),
            "slaščičarno"
        ),
        ("macintosh", Data([0x87, 0x8E, 0x92, 0x97, 0x9C]), "áéíóú"),
        ("ibm850", Data([0x9B, 0x9C, 0x9D, 0x9E]), "ø£Ø×"),
        (
            "koi8-u",
            Data([0xF0, 0xD2, 0xC9, 0xD7, 0xA6, 0xD4]),
            "Привіт"
        ),
    ]

    for (charset, bytes, expected) in cases {
        #expect(CharsetDecoder.decode(bytes, charset: charset) == expected)
    }
}

@Test
func unicodeAndMultibyteCharsetFamiliesMatchMailParser() {
    let cases: [(String, Data, String)] = [
        ("utf-7", Data("+ZYeB9FH6ckh5Pg-".utf8), "文致出版社"),
        (
            "utf-16le",
            Data([0xCF, 0x30, 0xED, 0x30, 0xFC, 0x30]),
            "ハロー"
        ),
        (
            "csshiftjis",
            Data([0x83, 0x6E, 0x83, 0x8D, 0x81, 0x5B]),
            "ハロー"
        ),
        (
            "big5-hkscs",
            Data([0xA7, 0x41, 0xA6, 0x6E, 0xA1, 0x41, 0xA5, 0x40, 0xAC, 0xC9]),
            "你好，世界"
        ),
        (
            "cseuckr",
            Data([0xBE, 0xC8, 0xB3, 0xE7, 0xC7, 0xCF, 0xBC, 0xBC, 0xBF, 0xE4]),
            "안녕하세요"
        ),
        (
            "csgb18030",
            Data([0xC4, 0xE3, 0xBA, 0xC3, 0xA3, 0xAC, 0xCA, 0xC0, 0xBD, 0xE7]),
            "你好，世界"
        ),
        ("x-user-defined", Data([0x80, 0xFF]), "\u{F780}\u{F7FF}"),
        ("replacement", Data("ignored".utf8), "\u{FFFD}"),
    ]

    for (charset, bytes, expected) in cases {
        #expect(CharsetDecoder.decode(bytes, charset: charset) == expected)
    }

    #expect(
        CharsetDecoder.decode(Data([0xF0, 0x28, 0x8C, 0x28]), charset: "unknown")
            == "�(�("
    )
}

@Test
func viceroyMultibyteMappingsMatchPinnedWHATWGVectors() {
    let vectors: [(String, [UInt8], String)] = [
        ("big5", [0xA1, 0x45], "\u{2027}"),
        ("big5", [0xA7, 0x41, 0xA1, 0x45], "你\u{2027}"),
        ("big5", [0x88, 0x62], "\u{00CA}\u{0304}"),
        ("big5", [0x88, 0x64], "\u{00CA}\u{030C}"),
        ("big5", [0x88, 0xA3], "\u{00EA}\u{0304}"),
        ("big5", [0x88, 0xA5], "\u{00EA}\u{030C}"),
        ("big5", [0x87, 0x45], "\u{27267}"),
        ("euc-jp", [0xA1, 0xBD], "\u{2015}"),
        ("euc-jp", [0x8F, 0xA2, 0xAF], "\u{02D8}"),
        ("euc-jp", [0xA5, 0xCF, 0xA1, 0xBD], "ハ\u{2015}"),
        ("euc-kr", [0x81, 0x41], "\u{AC02}"),
        ("euc-kr", [0xBE, 0xC8, 0x81, 0x41], "안\u{AC02}"),
        ("gb18030", [0xA3, 0xA0], "\u{3000}"),
        ("gb18030", [0xC4, 0xE3, 0xA3, 0xA0], "你\u{3000}"),
        ("gbk", [0xA2, 0xAB], "\u{E766}"),
        ("gbk", [0xC4, 0xE3, 0xA2, 0xAB], "你\u{E766}"),
        (
            "iso-2022-jp",
            [0x1B, 0x24, 0x40, 0x21, 0x3D, 0x1B, 0x28, 0x42],
            "\u{2015}"
        ),
        (
            "iso-2022-jp",
            [0x1B, 0x28, 0x49, 0x21, 0x1B, 0x28, 0x42],
            "\u{FF61}"
        ),
        (
            "iso-2022-jp",
            [
                0x1B, 0x28, 0x49, 0x21, 0x5F,
                0x1B, 0x24, 0x40, 0x21, 0x3D,
                0x1B, 0x28, 0x42, 0x5A,
            ],
            "\u{FF61}\u{FF9F}\u{2015}Z"
        ),
        ("shift_jis", [0x81, 0x5C], "\u{2015}"),
        ("shift_jis", [0x87, 0x40], "\u{2460}"),
        ("shift_jis", [0xF0, 0x40], "\u{E000}"),
        ("shift_jis", [0x83, 0x6E, 0x87, 0x40], "ハ\u{2460}"),
    ]
    for (charset, bytes, expected) in vectors {
        #expect(
            CharsetDecoder.decode(Data(bytes), charset: charset) == expected,
            Comment(rawValue: "WHATWG mapping failed: \(charset) \(bytes)")
        )
    }

    #expect(
        CharsetDecoder.decode(Data([0x81, 0x20]), charset: "big5")
            == "\u{FFFD} "
    )
}

@Test
func everyRustCharsetAliasRoutesToItsAdvertisedDecoderFamily() {
    // This is the complete 252-entry dispatch table from mail-parser 0.11.6
    // `src/decoders/charsets/map.rs`. Each family uses non-ASCII bytes so an
    // alias accidentally falling through to lossy UTF-8 cannot pass.
    let fixtures: [CharsetAliasFixture] = [
        .init(
            "850 cp850 cspc850multilingual ibm850",
            [0x9B, 0x9C, 0x9D, 0x9E],
            "ø£Ø×"
        ),
        .init(
            "866 cp866 csibm866 ibm866",
            [0x80, 0x90, 0xA0, 0xE0, 0xF0],
            "АРарЁ"
        ),
        .init(
            "ansi_x3.4_1968 ascii cp1252 cp819 csisolatin1 "
                + "cswindows1252 ibm819 iso88591 iso8859_1 iso_8859_1 "
                + "iso_8859_1:1987 iso_ir_100 l1 latin1 us_ascii "
                + "windows_1252 x_cp1252",
            [0x80, 0x35, 0x2E, 0x34],
            "€5.4"
        ),
        .init(
            "arabic asmo_708 csiso88596e csiso88596i csisolatinarabic "
                + "ecma_114 iso88596 iso8859_6 iso_8859_6 "
                + "iso_8859_6:1987 iso_8859_6_e iso_8859_6_i iso_ir_127",
            [0xE5, 0xD1, 0xCD, 0xC8, 0xC7],
            "مرحبا"
        ),
        .init(
            "big5 big5_hkscs cn_big5 csbig5 x_x_big5",
            [0xA7, 0x41, 0xA6, 0x6E, 0xA1, 0x41, 0xA5, 0x40, 0xAC, 0xC9],
            "你好，世界"
        ),
        .init(
            "chinese cp936 csgb2312 csgbk csiso58gb231280 gb_2312 "
                + "gb_2312_80 gbk iso_ir_58 ms936 windows_936 x_gbk",
            [0xC4, 0xE3, 0xBA, 0xC3, 0xA3, 0xAC, 0xCA, 0xC0, 0xBD, 0xE7],
            "你好，世界"
        ),
        .init(
            "cp1250 cswindows1250 windows_1250 x_cp1250",
            [0x73, 0x6C, 0x61, 0x9A, 0xE8, 0x69, 0xE8, 0x61, 0x72, 0x6E, 0x6F],
            "slaščičarno"
        ),
        .init(
            "cp1251 cswindows1251 windows_1251 x_cp1251",
            [0xCF, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2],
            "Привет"
        ),
        .init(
            "cp1253 cswindows1253 windows_1253 x_cp1253",
            [0xCA, 0xF9, 0xE4, 0xE9, 0xEA, 0xEF, 0xDF],
            "Κωδικοί"
        ),
        .init(
            "cp1254 cswindows1254 windows_1254 x_cp1254",
            [0x4B, 0x65, 0x62, 0x61, 0x62, 0xFD, 0x6D, 0xFD],
            "Kebabımı"
        ),
        .init(
            "cp1255 cswindows1255 windows_1255 x_cp1255",
            [0xF9, 0xEC, 0xE5, 0xED],
            "שלום"
        ),
        .init(
            "cp1256 cswindows1256 windows_1256 x_cp1256",
            [0xE3, 0xD1, 0xCD, 0xC8, 0xC7],
            "مرحبا"
        ),
        .init(
            "cp1257 cswindows1257 windows_1257 x_cp1257",
            [0x4D, 0x75, 0x20, 0x68, 0xF5, 0x6C, 0x6A, 0x75, 0x6B],
            "Mu hõljuk"
        ),
        .init(
            "cp1258 cswindows1258 windows_1258 x_cp1258",
            [0x58, 0x69, 0x6E, 0x20, 0x63, 0x68, 0xE0, 0x6F],
            "Xin chào"
        ),
        .init(
            "cseuckr csksc56011987 euc_kr iso_ir_149 korean "
                + "ks_c_5601_1987 ks_c_5601_1989 ksc5601 ksc_5601 "
                + "windows_949",
            [0xBE, 0xC8, 0xB3, 0xE7, 0xC7, 0xCF, 0xBC, 0xBC, 0xBF, 0xE4],
            "안녕하세요"
        ),
        .init(
            "cseucpkdfmtjapanese euc_jp "
                + "extended_unix_code_packed_format_for_japanese x_euc_jp",
            [
                0xA5, 0xCF, 0xA5, 0xED, 0xA1, 0xBC, 0xA1, 0xA6,
                0xA5, 0xEF, 0xA1, 0xBC, 0xA5, 0xEB, 0xA5, 0xC9,
            ],
            "ハロー・ワールド"
        ),
        .init(
            "csgb18030 gb18030 gb2312",
            [0xC4, 0xE3, 0x94, 0x39, 0xFC, 0x36, 0xC4, 0xE3],
            "你😀你"
        ),
        .init(
            "csiso2022jp iso_2022_jp",
            [
                0x1B, 0x24, 0x42, 0x25, 0x4F, 0x25, 0x6D, 0x21,
                0x3C, 0x21, 0x26, 0x25, 0x6F, 0x21, 0x3C, 0x25,
                0x6B, 0x25, 0x49, 0x1B, 0x28, 0x42,
            ],
            "ハロー・ワールド"
        ),
        .init(
            "csiso2022kr hz_gb_2312 iso_2022_cn iso_2022_cn_ext "
                + "iso_2022_kr replacement",
            Array("ignored".utf8),
            "�"
        ),
        .init(
            "csiso885913 iso885913 iso8859_13 iso_8859_13",
            [0xA1, 0xA5, 0xB5, 0xD0, 0xF0],
            "”„µŠš"
        ),
        .init(
            "csiso885914 iso885914 iso8859_14 iso_8859_14 "
                + "iso_8859_14:1998 iso_celtic iso_ir_199 l8 latin8",
            [0xA1, 0xA5, 0xB5, 0xD0, 0xF0],
            "ḂċṁŴŵ"
        ),
        .init(
            "csiso885915 csisolatin9 iso885915 iso8859_15 iso_8859_15 "
                + "l9 latin_9",
            [0xA4, 0xA6, 0xBC, 0xBD, 0xBE],
            "€ŠŒœŸ"
        ),
        .init(
            "csiso885916 iso_8859_16 iso_8859_16:2001 iso_ir_226 "
                + "l10 latin10",
            [0xA1, 0xA5, 0xB5, 0xD0, 0xF0],
            "Ą«”Đđ"
        ),
        .init(
            "csiso88598e csiso88598i csisolatinhebrew hebrew iso88598 "
                + "iso8859_8 iso_8859_8 iso_8859_8:1988 iso_8859_8_e "
                + "iso_8859_8_i iso_ir_138 logical visual",
            [0xF9, 0xEC, 0xE5, 0xED],
            "שלום"
        ),
        .init(
            "csisolatin2 iso88592 iso8859_2 iso_8859_2 "
                + "iso_8859_2:1987 iso_ir_101 l2 latin2",
            [0xA1, 0xA5, 0xB5, 0xD0, 0xF0],
            "ĄĽľĐđ"
        ),
        .init(
            "csisolatin3 iso88593 iso8859_3 iso_8859_3 "
                + "iso_8859_3:1988 iso_ir_109 l3 latin3",
            [0xA1, 0xA5, 0xB5, 0xD0, 0xF0],
            "Ħ�µ��"
        ),
        .init(
            "csisolatin4 iso88594 iso8859_4 iso_8859_4 "
                + "iso_8859_4:1988 iso_ir_110 l4 latin4",
            [0xA1, 0xA5, 0xB5, 0xD0, 0xF0],
            "ĄĨĩĐđ"
        ),
        .init(
            "csisolatin5 iso88599 iso8859_9 iso_8859_9 "
                + "iso_8859_9:1989 iso_ir_148 l5 latin5",
            [0xD0, 0xDD, 0xDE, 0xF0, 0xFD, 0xFE],
            "ĞİŞğış"
        ),
        .init(
            "csisolatin6 iso885910 iso8859_10 iso_8859_10 "
                + "iso_8859_10:1992 iso_ir_157 l6 latin6",
            [0xA1, 0xA5, 0xB5, 0xD0, 0xF0],
            "ĄĨĩÐð"
        ),
        .init(
            "csisolatincyrillic cyrillic iso88595 iso8859_5 iso_8859_5 "
                + "iso_8859_5:1988 iso_ir_144",
            [0xBF, 0xE0, 0xD8, 0xD2, 0xD5, 0xE2],
            "Привет"
        ),
        .init(
            "csisolatingreek ecma_118 elot_928 greek greek8 iso88597 "
                + "iso8859_7 iso_8859_7 iso_8859_7:1987 iso_ir_126 "
                + "sun_eu_greek",
            [0xC3, 0xE5, 0xE9, 0xDC],
            "Γειά"
        ),
        .init(
            "cskoi8r koi koi8 koi8_r",
            [0xF0, 0xD2, 0xC9, 0xD7, 0xC5, 0xD4],
            "Привет"
        ),
        .init(
            "cskoi8u koi8_ru koi8_u",
            [0xF0, 0xD2, 0xC9, 0xD7, 0xA6, 0xD4],
            "Привіт"
        ),
        .init(
            "csmacintosh mac macintosh x_mac_roman",
            [0x87, 0x8E, 0x92, 0x97, 0x9C],
            "áéíóú"
        ),
        .init(
            "csshiftjis ms932 ms_kanji shift_jis sjis windows_31j x_sjis",
            [
                0x83, 0x6E, 0x83, 0x8D, 0x81, 0x5B, 0x81, 0x45,
                0x83, 0x8F, 0x81, 0x5B, 0x83, 0x8B, 0x83, 0x68,
            ],
            "ハロー・ワールド"
        ),
        .init(
            "cstis620 iso885911 iso8859_11 iso_8859_11 tis_620",
            [0xC3, 0xCB, 0xD1, 0xCA, 0xCA, 0xD3],
            "รหัสสำ"
        ),
        .init(
            "csunicode csutf16 iso_10646_ucs_2 ucs_2 unicode unicodefeff "
                + "utf_16",
            [0xFF, 0xFE, 0xE1, 0x00, 0xE9, 0x00, 0xED, 0x00],
            "áéí"
        ),
        .init(
            "csutf16be unicodefffe utf_16be",
            [0x30, 0xCF, 0x30, 0xED, 0x30, 0xFC],
            "ハロー"
        ),
        .init(
            "csutf16le utf_16le",
            [0xCF, 0x30, 0xED, 0x30, 0xFC, 0x30],
            "ハロー"
        ),
        .init(
            "csutf7 utf_7",
            Array("+ZYeB9FH6ckh5Pg-".utf8),
            "文致出版社"
        ),
        .init(
            "cswindows874 dos_874 windows_874",
            [0x80, 0xA1, 0xC0, 0xDF, 0xFB],
            "€กภ฿๛"
        ),
        .init(
            "x_mac_cyrillic x_mac_ukrainian",
            [0x8F, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2],
            "Привет"
        ),
        .init(
            "x_user_defined",
            [0x80, 0xFF],
            "\u{F780}\u{F7FF}"
        ),
    ]

    var testedAliases = Set<String>()
    for fixture in fixtures {
        for alias in fixture.aliases {
            #expect(
                testedAliases.insert(alias).inserted,
                Comment(rawValue: "duplicate Rust charset alias: \(alias)")
            )
            #expect(
                CharsetDecoder.recognizes(alias),
                Comment(rawValue: "unrecognized Rust charset alias: \(alias)")
            )
            #expect(
                CharsetDecoder.decode(fixture.bytes, charset: alias)
                    == fixture.expected,
                Comment(rawValue: "wrong decoder selected for charset alias: \(alias)")
            )

            let wireStyleAlias = alias
                .replacingOccurrences(of: "_", with: "-")
                .uppercased()
            #expect(CharsetDecoder.recognizes(wireStyleAlias))
            #expect(
                CharsetDecoder.decode(fixture.bytes, charset: wireStyleAlias)
                    == fixture.expected,
                Comment(
                    rawValue: "wrong decoder selected for normalized alias: "
                        + wireStyleAlias
                )
            )
        }
    }

    #expect(testedAliases.count == 252)
    #expect(
        CharsetDecoder.decode(
            Data([0x81, 0x35, 0xF4, 0x37]),
            charset: "gb18030"
        ) == "\u{E7C7}"
    )
}

@Test
func everySingleByteMappingMatchesPinnedRustAndWHATWG() {
    // These fingerprints cover all 256 entries in every single-byte table,
    // including the pinned U+FFFD mappings for undefined source bytes.
    let fixtures: [SingleByteParityFixture] = [
        .init("iso-8859-2", 0xE79122F05C7FAD32),
        .init("iso-8859-3", 0x98ECC9009E339B63),
        .init("iso-8859-4", 0x211A811C0B09B61E),
        .init("iso-8859-5", 0xA984B5CA60F1B464),
        .init("iso-8859-6", 0x662715AD36598D14),
        .init("iso-8859-7", 0xDF00BCC27D160614),
        .init("iso-8859-8", 0x131868C65E193FD7),
        .init("iso-8859-9", 0xE2147AB9B3B6C640),
        .init("iso-8859-10", 0x7C9789176A4A021F),
        .init("iso-8859-13", 0xC94A5C63040DBC9E),
        .init("iso-8859-14", 0x679EBDA0DF4BE881),
        .init("iso-8859-15", 0xF55BEA4AF24B32C0),
        .init("iso-8859-16", 0xB00598352CE663D0),
        .init("ibm850", 0x9AF820F6E0BBA3A7),
        .init("koi8-r", 0x47569CE7B460C2CA),
        .init("koi8-u", 0x2F57FA93FC54258B),
        .init("tis-620", 0x53A45530A983191F),
        .init("cp1250", 0x9383FD5CA5693716),
        .init("cp1251", 0x19A1D4FDE049FB49),
        .init("cp1252", 0x5575820464519F1E),
        .init("cp1253", 0x0A1DEE65BA1FFC54),
        .init("cp1254", 0xA3719EF0327CD0CE),
        .init("cp1255", 0x5D2869DBE6D9ACD7),
        .init("cp1256", 0x89EF7D6FEB89DB34),
        .init("cp1257", 0x2F7CA9D9684AD5EA),
        .init("cp1258", 0xB84DF16E3202A552),
        .init("macintosh", 0xF21B1A1AF8AA02B5),
        .init("ibm866", 0x43B90F129C871C61),
        .init("x-mac-cyrillic", 0xED7797043A5ADC8B),
        .init("windows-874", 0xF0A9895668967B27),
    ]
    let bytes = Data((0...255).map(UInt8.init))

    for fixture in fixtures {
        let decoded = CharsetDecoder.decode(bytes, charset: fixture.charset)
        let scalars = decoded.unicodeScalars.map(\.value)

        #expect(
            scalars.count == bytes.count,
            Comment(rawValue: "wrong scalar count for \(fixture.charset)")
        )
        #expect(
            singleByteFingerprint(bytes: bytes, scalars: scalars)
                == fixture.expectedFingerprint,
            Comment(rawValue: "mapping mismatch for \(fixture.charset)")
        )
    }

    #expect(fixtures.count * bytes.count == 7_680)
}

@Test
func rustUTF8LabelsUseTheIntentionalLossyUTF8Fallback() {
    let labels = [
        "utf8",
        "utf-8",
        "unicode11utf8",
        "unicode20utf8",
        "x-unicode20utf8",
        "unicode-1-1-utf-8",
    ]
    let bytes = Data("Zażółć gęślą jaźń".utf8)

    for label in labels {
        #expect(CharsetDecoder.recognizes(label) == false)
        #expect(CharsetDecoder.decode(bytes, charset: label) == "Zażółć gęślą jaźń")
    }
}

@Test
func htmlConversionHandlesHiddenContentCommentsAndEntities() {
    let html = "<head>head</head><style>style</style><script>script</script>"
        + "<template>template</template><!-- comment -->"
        + "<p>what is &heartsuit;?</p><p>&#x000DF;&Abreve;&#914;&gamma;</p>"

    #expect(HTMLConverter.htmlToText(html) == "what is ♥?\nßĂΒγ\n")
    #expect(
        HTMLConverter.htmlToText("&CounterClockwiseContourIntegral; &curvearrowright;")
            == "∳ ↷"
    )
    #expect(HTMLConverter.htmlToText("&#xFFFFFFF;") == "�")
}

@Test
func remainingRustHTMLToTextVectorsMatch() {
    let cases: [(String, String)] = [
        ("<html>hello<br/>world<br/></html>", "hello\nworld\n"),
        ("<html>using &lt;><br/></html>", "using <>\n"),
        ("test <not br/>tag<br />", "test tag\n"),
        ("<>< ><tag\n/>>hello    world< br \n />", ">hello world\n"),
        (
            "<head><title>ignore head</title><not head>xyz</not head></head>"
                + "<h1>&lt;body&gt;</h1>",
            "<body>"
        ),
        (
            "<p>what is &heartsuit;?</p><p>&#x000DF;&Abreve;&#914;&gamma; "
                + "don&apos;t hurt me.</p>",
            "what is ♥?\nßĂΒγ don't hurt me.\n"
        ),
        (
            "<!--[if mso]><style type=\"text/css\">body, table, td, a, p, "
                + "span, ul, li {font-family: Arial, sans-serif!important;}"
                + "</style><![endif]-->this is <!-- <> < < < < ignore  > -> "
                + "here -->the actual<!--> text",
            "this is the actual text"
        ),
        (
            "   < p >  hello < / p > < p > world < / p >   !!! < br > ",
            "hello\nworld\n!!!\n"
        ),
        (
            " <p>please unsubscribe <a href=#>here</a>.</p> ",
            "please unsubscribe here.\n"
        ),
    ]

    for (html, expected) in cases {
        #expect(
            HTMLConverter.htmlToText(html) == expected,
            Comment(rawValue: "Rust html_to_text vector failed: \(html)")
        )
    }
}

@Test
func remainingRustHTMLEntityVectorsMatch() {
    let cases: [(String, String)] = [
        ("&lt;", "<"),
        ("&#32;", " "),
        ("&#x20;", " "),
        ("&nbsp;", "\u{00A0}"),
        ("&rarr;", "→"),
        ("&hmmm", "&hmmm"),
    ]

    for (entity, expected) in cases {
        #expect(
            HTMLConverter.htmlToText(entity) == expected,
            Comment(rawValue: "Rust HTML entity vector failed: \(entity)")
        )
    }
}

@Test
func textToHTMLMatchesMailParserAndIsNotASanitizer() {
    #expect(
        HTMLConverter.textToHTML("one < two & three\r\nfour")
            == "<html><body>one &lt; two & three<br/>four</body></html>"
    )

    #expect(
        HTMLConverter.textToHTML("hello\nworld\n")
            == "<html><body>hello<br/>world<br/></body></html>"
    )
    #expect(
        HTMLConverter.textToHTML("using <>\n")
            == "<html><body>using &lt;><br/></body></html>"
    )
}

@Test
func previewsUseUTF8ByteLimitsWithoutSplittingScalars() {
    #expect(HTMLConverter.previewText("長沮、桀溺", maxLength: 10) == "長沮...")
    #expect(HTMLConverter.previewText("éééé", maxLength: 7) == "éé...")
    #expect(HTMLConverter.previewText("éééé", maxLength: 6) == "ééé")
    #expect(
        HTMLConverter.previewHTML("<p>長沮、桀溺</p>", maxLength: 10)
            == "長沮..."
    )
}

@Test
func rustLongTextPreviewVectorsMatch() {
    let western = "J'interdis aux marchands de vanter trop leurs marchandises. "
        + "Car ils se fontvite pédagogues et t'enseignent comme but ce qui "
        + "n'est par essence qu'un moyen, et te trompant ainsi sur la route "
        + "à suivre les voilà bientôt qui te dégradent, car si leur musique "
        + "est vulgaire ils te fabriquent pour te la vendre une âme vulgaire.\n"
        + "— Antoine de Saint-Exupéry, Citadelle (1948)"
    let chinese = "長沮、桀溺耦而耕，孔子過之，使子路問津焉。長沮曰：「夫執輿者為誰？」"
        + "子路曰：「為孔丘。」曰：「是魯孔丘與？」曰：「是也。」曰：「是知津矣。」問於桀溺，"
        + "桀溺曰：「子為誰？」曰：「為仲由。」曰：「是魯孔丘之徒與？」對曰：「然。"
        + "」曰：「滔滔者天下皆是也，而誰以易之？且而與其從辟人之士也，豈若從"
        + "辟世之士哉？」耰而不輟。子路行以告。夫子憮然曰：「鳥獸不可與同群，吾非斯人之徒"
        + "與而誰與？天下有道，丘不與易也。」"
        + "子路從而後，遇丈人，以杖荷蓧。子路問曰：「子見夫子乎？」丈人曰：「四體不勤，"
        + "五穀不分。孰為夫子？」植其杖而芸。子路拱而立。止子路宿，殺雞為黍而食之，見其二"
        + "子焉。明日，子路行以告。子曰：「隱者也。」使子路反見之。至則行矣。子路曰：「"
        + "不仕無義。長幼之節，不可廢也；君臣之義，如之何其廢之？欲潔其身，而亂大倫。君"
        + "子之仕也，行其義也。道之不行，已知之矣。」"

    #expect(
        HTMLConverter.truncateText(western, maxLength: 110)
            == "J'interdis aux marchands de vanter trop leurs marchandises. "
                + "Car ils se fontvite pédagogues et t'enseignent..."
    )
    #expect(
        HTMLConverter.truncateText(chinese, maxLength: 110)
            == "長沮、桀溺耦而耕，孔子過之，使子路問津焉。長沮曰：「夫執輿者為誰？」子..."
    )
}

@Test
func htmlTruncationDoesNotCutThroughTheMostRecentTag() {
    #expect(
        HTMLConverter.truncateHTML(
            "<html>hello<br/>world<br/></html>",
            maxLength: 25
        ) == "<html>hello<br/>world..."
    )

    let remainingCases: [(String, String)] = [
        ("<html>using &lt;><br/></html>", "<html>using &lt;><br/>..."),
        (
            "test <not br/>tag<br />test <not br/>tag<br />",
            "test <not br/>tag..."
        ),
        (
            "<>< ><tag\n/>>hello    world< br \n />",
            "<>< ><tag\n/>>hello    ..."
        ),
        (
            "<head><title>ignore head</title><not head>xyz</not head></head>"
                + "<h1>&lt;body&gt;</h1>",
            "<head><title>ignore he..."
        ),
        (
            "<p>what is &heartsuit;?</p><p>&#x000DF;&Abreve;&#914;&gamma; "
                + "don&apos;t hurt me.</p>",
            "<p>what is &heartsuit;..."
        ),
        (
            "<!-- <> < < < -->the actual<!--> text",
            "<!-- <> < < < -->the a..."
        ),
        (
            "   < p >  hello < / p > < p > world < / p >   !!! < br > ",
            "   < p >  hello ..."
        ),
        (
            " <p>please unsubscribe <a href=#>here</a>.</p> ",
            " <p>please unsubscribe..."
        ),
    ]

    for (html, expected) in remainingCases {
        #expect(
            HTMLConverter.truncateHTML(html, maxLength: 25) == expected,
            Comment(rawValue: "Rust truncate_html vector failed: \(html)")
        )
    }
}

private struct CharsetAliasFixture {
    let aliases: [String]
    let bytes: Data
    let expected: String

    init(_ aliases: String, _ bytes: [UInt8], _ expected: String) {
        self.aliases = aliases.split(separator: " ").map(String.init)
        self.bytes = Data(bytes)
        self.expected = expected
    }
}

private struct SingleByteParityFixture {
    let charset: String
    let expectedFingerprint: UInt64

    init(_ charset: String, _ expectedFingerprint: UInt64) {
        self.charset = charset
        self.expectedFingerprint = expectedFingerprint
    }
}

private func singleByteFingerprint(
    bytes: Data,
    scalars: [UInt32]
) -> UInt64 {
    var fingerprint: UInt64 = 14_695_981_039_346_656_037

    func mix(_ byte: UInt8) {
        fingerprint ^= UInt64(byte)
        fingerprint = fingerprint &* 1_099_511_628_211
    }

    for (byte, scalar) in zip(bytes, scalars) {
        mix(byte)
        mix(UInt8(truncatingIfNeeded: scalar))
        mix(UInt8(truncatingIfNeeded: scalar >> 8))
        mix(UInt8(truncatingIfNeeded: scalar >> 16))
        mix(UInt8(truncatingIfNeeded: scalar >> 24))
    }

    return fingerprint
}
