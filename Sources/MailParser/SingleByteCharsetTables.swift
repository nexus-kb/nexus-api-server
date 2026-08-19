/*
 * SPDX-FileCopyrightText: 2020 Stalwart Labs LLC <hello@stalw.art>
 *
 * SPDX-License-Identifier: Apache-2.0 OR MIT
 *
 * Generated from mail-parser 0.11.6's single-byte tables at commit b4366b7
 * plus encoding_rs/WHATWG tables for IBM866, x-mac-cyrillic, and Windows-874.
 * Each Base64 payload stores the 128 upper-half Unicode scalar values as
 * big-endian UInt16 values; all lower halves are ASCII.
 */

import Foundation

enum SingleByteCharsetTable: Int, Sendable {
    case iso8859_2
    case iso8859_3
    case iso8859_4
    case iso8859_5
    case iso8859_6
    case iso8859_7
    case iso8859_8
    case iso8859_9
    case iso8859_10
    case iso8859_13
    case iso8859_14
    case iso8859_15
    case iso8859_16
    case ibm850
    case koi8R
    case koi8U
    case tis620
    case cp1250
    case cp1251
    case cp1252
    case cp1253
    case cp1254
    case cp1255
    case cp1256
    case cp1257
    case cp1258
    case macintosh
    case ibm866
    case macCyrillic
    case windows874

    func scalar(for byte: UInt8) -> UnicodeScalar {
        guard byte >= 0x80 else {
            return UnicodeScalar(UInt32(byte))!
        }
        let mapping = Self.upperHalves[rawValue]
        let offset = Int(byte - 0x80) * 2
        let value = UInt32(mapping[offset]) << 8
            | UInt32(mapping[offset + 1])
        return UnicodeScalar(value)!
    }

    private static let upperHalves: [Data] = [
        Data(
            base64Encoded: """
            AIAAgQCCAIMAhACFAIYAhwCIAIkAigCLAIwAjQCOAI8AkACRAJIAkwCUAJUAlgCX
            AJgAmQCaAJsAnACdAJ4AnwCgAQQC2AFBAKQBPQFaAKcAqAFgAV4BZAF5AK0BfQF7
            ALABBQLbAUIAtAE+AVsCxwC4AWEBXwFlAXoC3QF+AXwBVADBAMIBAgDEATkBBgDH
            AQwAyQEYAMsBGgDNAM4BDgEQAUMBRwDTANQBUADWANcBWAFuANoBcADcAN0BYgDf
            AVUA4QDiAQMA5AE6AQcA5wENAOkBGQDrARsA7QDuAQ8BEQFEAUgA8wD0AVEA9gD3
            AVkBbwD6AXEA/AD9AWMC2Q==
            """,
            options: .ignoreUnknownCharacters
        )!,
        Data(
            base64Encoded: """
            AIAAgQCCAIMAhACFAIYAhwCIAIkAigCLAIwAjQCOAI8AkACRAJIAkwCUAJUAlgCX
            AJgAmQCaAJsAnACdAJ4AnwCgASYC2ACjAKT//QEkAKcAqAEwAV4BHgE0AK3//QF7
            ALABJwCyALMAtAC1ASUAtwC4ATEBXwEfATUAvf/9AXwAwADBAML//QDEAQoBCADH
            AMgAyQDKAMsAzADNAM4Az//9ANEA0gDTANQBIADWANcBHADZANoA2wDcAWwBXADf
            AOAA4QDi//0A5AELAQkA5wDoAOkA6gDrAOwA7QDuAO///QDxAPIA8wD0ASEA9gD3
            AR0A+QD6APsA/AFtAV0C2Q==
            """,
            options: .ignoreUnknownCharacters
        )!,
        Data(
            base64Encoded: """
            AIAAgQCCAIMAhACFAIYAhwCIAIkAigCLAIwAjQCOAI8AkACRAJIAkwCUAJUAlgCX
            AJgAmQCaAJsAnACdAJ4AnwCgAQQBOAFWAKQBKAE7AKcAqAFgARIBIgFmAK0BfQCv
            ALABBQLbAVcAtAEpATwCxwC4AWEBEwEjAWcBSgF+AUsBAADBAMIAwwDEAMUAxgEu
            AQwAyQEYAMsBFgDNAM4BKgEQAUUBTAE2ANQA1QDWANcA2AFyANoA2wDcAWgBagDf
            AQEA4QDiAOMA5ADlAOYBLwENAOkBGQDrARcA7QDuASsBEQFGAU0BNwD0APUA9gD3
            APgBcwD6APsA/AFpAWsC2Q==
            """,
            options: .ignoreUnknownCharacters
        )!,
        Data(
            base64Encoded: """
            AIAAgQCCAIMAhACFAIYAhwCIAIkAigCLAIwAjQCOAI8AkACRAJIAkwCUAJUAlgCX
            AJgAmQCaAJsAnACdAJ4AnwCgBAEEAgQDBAQEBQQGBAcECAQJBAoECwQMAK0EDgQP
            BBAEEQQSBBMEFAQVBBYEFwQYBBkEGgQbBBwEHQQeBB8EIAQhBCIEIwQkBCUEJgQn
            BCgEKQQqBCsELAQtBC4ELwQwBDEEMgQzBDQENQQ2BDcEOAQ5BDoEOwQ8BD0EPgQ/
            BEAEQQRCBEMERARFBEYERwRIBEkESgRLBEwETQROBE8hFgRRBFIEUwRUBFUEVgRX
            BFgEWQRaBFsEXACnBF4EXw==
            """,
            options: .ignoreUnknownCharacters
        )!,
        Data(
            base64Encoded: """
            AIAAgQCCAIMAhACFAIYAhwCIAIkAigCLAIwAjQCOAI8AkACRAJIAkwCUAJUAlgCX
            AJgAmQCaAJsAnACdAJ4AnwCg//3//f/9AKT//f/9//3//f/9//3//QYMAK3//f/9
            //3//f/9//3//f/9//3//f/9//3//QYb//3//f/9Bh///QYhBiIGIwYkBiUGJgYn
            BigGKQYqBisGLAYtBi4GLwYwBjEGMgYzBjQGNQY2BjcGOAY5Bjr//f/9//3//f/9
            BkAGQQZCBkMGRAZFBkYGRwZIBkkGSgZLBkwGTQZOBk8GUAZRBlL//f/9//3//f/9
            //3//f/9//3//f/9//3//Q==
            """,
            options: .ignoreUnknownCharacters
        )!,
        Data(
            base64Encoded: """
            AIAAgQCCAIMAhACFAIYAhwCIAIkAigCLAIwAjQCOAI8AkACRAJIAkwCUAJUAlgCX
            AJgAmQCaAJsAnACdAJ4AnwCgIBggGQCj//3//QCmAKcAqACp//0AqwCsAK3//SAV
            ALAAsQCyALMDhAOFA4YAtwOIA4kDigC7A4wAvQOOA48DkAORA5IDkwOUA5UDlgOX
            A5gDmQOaA5sDnAOdA54DnwOgA6H//QOjA6QDpQOmA6cDqAOpA6oDqwOsA60DrgOv
            A7ADsQOyA7MDtAO1A7YDtwO4A7kDugO7A7wDvQO+A78DwAPBA8IDwwPEA8UDxgPH
            A8gDyQPKA8sDzAPNA87//Q==
            """,
            options: .ignoreUnknownCharacters
        )!,
        Data(
            base64Encoded: """
            AIAAgQCCAIMAhACFAIYAhwCIAIkAigCLAIwAjQCOAI8AkACRAJIAkwCUAJUAlgCX
            AJgAmQCaAJsAnACdAJ4AnwCg//0AogCjAKQApQCmAKcAqACpANcAqwCsAK0ArgCv
            ALAAsQCyALMAtAC1ALYAtwC4ALkA9wC7ALwAvQC+//3//f/9//3//f/9//3//f/9
            //3//f/9//3//f/9//3//f/9//3//f/9//3//f/9//3//f/9//3//f/9//3//SAX
            BdAF0QXSBdMF1AXVBdYF1wXYBdkF2gXbBdwF3QXeBd8F4AXhBeIF4wXkBeUF5gXn
            BegF6QXq//3//SAOIA///Q==
            """,
            options: .ignoreUnknownCharacters
        )!,
        Data(
            base64Encoded: """
            AIAAgQCCAIMAhACFAIYAhwCIAIkAigCLAIwAjQCOAI8AkACRAJIAkwCUAJUAlgCX
            AJgAmQCaAJsAnACdAJ4AnwCgAKEAogCjAKQApQCmAKcAqACpAKoAqwCsAK0ArgCv
            ALAAsQCyALMAtAC1ALYAtwC4ALkAugC7ALwAvQC+AL8AwADBAMIAwwDEAMUAxgDH
            AMgAyQDKAMsAzADNAM4AzwEeANEA0gDTANQA1QDWANcA2ADZANoA2wDcATABXgDf
            AOAA4QDiAOMA5ADlAOYA5wDoAOkA6gDrAOwA7QDuAO8BHwDxAPIA8wD0APUA9gD3
            APgA+QD6APsA/AExAV8A/w==
            """,
            options: .ignoreUnknownCharacters
        )!,
        Data(
            base64Encoded: """
            AIAAgQCCAIMAhACFAIYAhwCIAIkAigCLAIwAjQCOAI8AkACRAJIAkwCUAJUAlgCX
            AJgAmQCaAJsAnACdAJ4AnwCgAQQBEgEiASoBKAE2AKcBOwEQAWABZgF9AK0BagFK
            ALABBQETASMBKwEpATcAtwE8AREBYQFnAX4gFQFrAUsBAADBAMIAwwDEAMUAxgEu
            AQwAyQEYAMsBFgDNAM4AzwDQAUUBTADTANQA1QDWAWgA2AFyANoA2wDcAN0A3gDf
            AQEA4QDiAOMA5ADlAOYBLwENAOkBGQDrARcA7QDuAO8A8AFGAU0A8wD0APUA9gFp
            APgBcwD6APsA/AD9AP4BOA==
            """,
            options: .ignoreUnknownCharacters
        )!,
        Data(
            base64Encoded: """
            AIAAgQCCAIMAhACFAIYAhwCIAIkAigCLAIwAjQCOAI8AkACRAJIAkwCUAJUAlgCX
            AJgAmQCaAJsAnACdAJ4AnwCgIB0AogCjAKQgHgCmAKcA2ACpAVYAqwCsAK0ArgDG
            ALAAsQCyALMgHAC1ALYAtwD4ALkBVwC7ALwAvQC+AOYBBAEuAQABBgDEAMUBGAES
            AQwAyQF5ARYBIgE2ASoBOwFgAUMBRQDTAUwA1QDWANcBcgFBAVoBagDcAXsBfQDf
            AQUBLwEBAQcA5ADlARkBEwENAOkBegEXASMBNwErATwBYQFEAUYA8wFNAPUA9gD3
            AXMBQgFbAWsA/AF8AX4gGQ==
            """,
            options: .ignoreUnknownCharacters
        )!,
        Data(
            base64Encoded: """
            AIAAgQCCAIMAhACFAIYAhwCIAIkAigCLAIwAjQCOAI8AkACRAJIAkwCUAJUAlgCX
            AJgAmQCaAJsAnACdAJ4AnwCgHgIeAwCjAQoBCx4KAKcegACpHoIeCx7yAK0ArgF4
            Hh4eHwEgASEeQB5BALYeVh6BHlcegx5gHvMehB6FHmEAwADBAMIAwwDEAMUAxgDH
            AMgAyQDKAMsAzADNAM4AzwF0ANEA0gDTANQA1QDWHmoA2ADZANoA2wDcAN0BdgDf
            AOAA4QDiAOMA5ADlAOYA5wDoAOkA6gDrAOwA7QDuAO8BdQDxAPIA8wD0APUA9h5r
            APgA+QD6APsA/AD9AXcA/w==
            """,
            options: .ignoreUnknownCharacters
        )!,
        Data(
            base64Encoded: """
            AIAAgQCCAIMAhACFAIYAhwCIAIkAigCLAIwAjQCOAI8AkACRAJIAkwCUAJUAlgCX
            AJgAmQCaAJsAnACdAJ4AnwCgAKEAogCjIKwApQFgAKcBYQCpAKoAqwCsAK0ArgCv
            ALAAsQCyALMBfQC1ALYAtwF+ALkAugC7AVIBUwF4AL8AwADBAMIAwwDEAMUAxgDH
            AMgAyQDKAMsAzADNAM4AzwDQANEA0gDTANQA1QDWANcA2ADZANoA2wDcAN0A3gDf
            AOAA4QDiAOMA5ADlAOYA5wDoAOkA6gDrAOwA7QDuAO8A8ADxAPIA8wD0APUA9gD3
            APgA+QD6APsA/AD9AP4A/w==
            """,
            options: .ignoreUnknownCharacters
        )!,
        Data(
            base64Encoded: """
            AIAAgQCCAIMAhACFAIYAhwCIAIkAigCLAIwAjQCOAI8AkACRAJIAkwCUAJUAlgCX
            AJgAmQCaAJsAnACdAJ4AnwCgAQQBBQFBIKwAqwFgAKcBYQCpAhggHgF5AK0BegF7
            ALAAsQEMAUIBfSAdALYAtwF+AQ0CGQC7AVIBUwF4AXwAwADBAMIBAgDEAQYAxgDH
            AMgAyQDKAMsAzADNAM4AzwEQAUMA0gDTANQBUADWAVoBcADZANoA2wDcARgCGgDf
            AOAA4QDiAQMA5AEHAOYA5wDoAOkA6gDrAOwA7QDuAO8BEQFEAPIA8wD0AVEA9gFb
            AXEA+QD6APsA/AEZAhsA/w==
            """,
            options: .ignoreUnknownCharacters
        )!,
        Data(
            base64Encoded: """
            AMcA/ADpAOIA5ADgAOUA5wDqAOsA6ADvAO4A7ADEAMUAyQDmAMYA9AD2APIA+wD5
            AP8A1gDcAPgAowDYANcBkgDhAO0A8wD6APEA0QCqALoAvwCuAKwAvQC8AKEAqwC7
            JZElkiWTJQIlJADBAMIAwACpJWMlUSVXJV0AogClJRAlFCU0JSwlHCUAJTwA4wDD
            JVolVCVpJWYlYCVQJWwApADwANAAygDLAMgBMQDNAM4AzyUYJQwliCWEAKYAzCWA
            ANMA3wDUANIA9QDVALUA/gDeANoA2wDZAP0A3QCvALQArQCxIBcAvgC2AKcA9wC4
            ALAAqAC3ALkAswCyJaAAoA==
            """,
            options: .ignoreUnknownCharacters
        )!,
        Data(
            base64Encoded: """
            JQAlAiUMJRAlFCUYJRwlJCUsJTQlPCWAJYQliCWMJZAlkSWSJZMjICWgIhkiGiJI
            ImQiZQCgIyEAsACyALcA9yVQJVElUgRRJVMlVCVVJVYlVyVYJVklWiVbJVwlXSVe
            JV8lYCVhBAElYiVjJWQlZSVmJWclaCVpJWolayVsAKkETgQwBDEERgQ0BDUERAQz
            BEUEOAQ5BDoEOwQ8BD0EPgQ/BE8EQARBBEIEQwQ2BDIETARLBDcESARNBEkERwRK
            BC4EEAQRBCYEFAQVBCQEEwQlBBgEGQQaBBsEHAQdBB4EHwQvBCAEIQQiBCMEFgQS
            BCwEKwQXBCgELQQpBCcEKg==
            """,
            options: .ignoreUnknownCharacters
        )!,
        Data(
            base64Encoded: """
            JQAlAiUMJRAlFCUYJRwlJCUsJTQlPCWAJYQliCWMJZAlkSWSJZMjICWgIhkiGiJI
            ImQiZQCgIyEAsACyALcA9yVQJVElUgRRBFQlVARWBFclVyVYJVklWiVbBJElXSVe
            JV8lYCVhBAEEBCVjBAYEByVmJWclaCVpJWoEkCVsAKkETgQwBDEERgQ0BDUERAQz
            BEUEOAQ5BDoEOwQ8BD0EPgQ/BE8EQARBBEIEQwQ2BDIETARLBDcESARNBEkERwRK
            BC4EEAQRBCYEFAQVBCQEEwQlBBgEGQQaBBsEHAQdBB4EHwQvBCAEIQQiBCMEFgQS
            BCwEKwQXBCgELQQpBCcEKg==
            """,
            options: .ignoreUnknownCharacters
        )!,
        Data(
            base64Encoded: """
            //3//f/9//3//f/9//3//f/9//3//f/9//3//f/9//3//f/9//3//f/9//3//f/9
            //3//f/9//3//f/9//3//f/9DgEOAg4DDgQOBQ4GDgcOCA4JDgoOCw4MDg0ODg4P
            DhAOEQ4SDhMOFA4VDhYOFw4YDhkOGg4bDhwOHQ4eDh8OIA4hDiIOIw4kDiUOJg4n
            DigOKQ4qDisOLA4tDi4OLw4wDjEOMg4zDjQONQ42DjcOOA45Djr//f/9//3//Q4/
            DkAOQQ5CDkMORA5FDkYORw5IDkkOSg5LDkwOTQ5ODk8OUA5RDlIOUw5UDlUOVg5X
            DlgOWQ5aDlv//f/9//3//Q==
            """,
            options: .ignoreUnknownCharacters
        )!,
        Data(
            base64Encoded: """
            IKz//SAa//0gHiAmICAgIf/9IDABYCA5AVoBZAF9AXn//SAYIBkgHCAdICIgEyAU
            //0hIgFhIDoBWwFlAX4BegCgAscC2AFBAKQBBACmAKcAqACpAV4AqwCsAK0ArgF7
            ALAAsQLbAUIAtAC1ALYAtwC4AQUBXwC7AT0C3QE+AXwBVADBAMIBAgDEATkBBgDH
            AQwAyQEYAMsBGgDNAM4BDgEQAUMBRwDTANQBUADWANcBWAFuANoBcADcAN0BYgDf
            AVUA4QDiAQMA5AE6AQcA5wENAOkBGQDrARsA7QDuAQ8BEQFEAUgA8wD0AVEA9gD3
            AVkBbwD6AXEA/AD9AWMC2Q==
            """,
            options: .ignoreUnknownCharacters
        )!,
        Data(
            base64Encoded: """
            BAIEAyAaBFMgHiAmICAgISCsIDAECSA5BAoEDAQLBA8EUiAYIBkgHCAdICIgEyAU
            //0hIgRZIDoEWgRcBFsEXwCgBA4EXgQIAKQEkACmAKcEAQCpBAQAqwCsAK0ArgQH
            ALAAsQQGBFYEkQC1ALYAtwRRIRYEVAC7BFgEBQRVBFcEEAQRBBIEEwQUBBUEFgQX
            BBgEGQQaBBsEHAQdBB4EHwQgBCEEIgQjBCQEJQQmBCcEKAQpBCoEKwQsBC0ELgQv
            BDAEMQQyBDMENAQ1BDYENwQ4BDkEOgQ7BDwEPQQ+BD8EQARBBEIEQwREBEUERgRH
            BEgESQRKBEsETARNBE4ETw==
            """,
            options: .ignoreUnknownCharacters
        )!,
        Data(
            base64Encoded: """
            IKz//SAaAZIgHiAmICAgIQLGIDABYCA5AVL//QF9//3//SAYIBkgHCAdICIgEyAU
            AtwhIgFhIDoBU//9AX4BeACgAKEAogCjAKQApQCmAKcAqACpAKoAqwCsAK0ArgCv
            ALAAsQCyALMAtAC1ALYAtwC4ALkAugC7ALwAvQC+AL8AwADBAMIAwwDEAMUAxgDH
            AMgAyQDKAMsAzADNAM4AzwDQANEA0gDTANQA1QDWANcA2ADZANoA2wDcAN0A3gDf
            AOAA4QDiAOMA5ADlAOYA5wDoAOkA6gDrAOwA7QDuAO8A8ADxAPIA8wD0APUA9gD3
            APgA+QD6APsA/AD9AP4A/w==
            """,
            options: .ignoreUnknownCharacters
        )!,
        Data(
            base64Encoded: """
            IKz//SAaAZIgHiAmICAgIf/9IDD//SA5//3//f/9//3//SAYIBkgHCAdICIgEyAU
            //0hIv/9IDr//f/9//3//QCgA4UDhgCjAKQApQCmAKcAqACp//0AqwCsAK0AriAV
            ALAAsQCyALMDhAC1ALYAtwOIA4kDigC7A4wAvQOOA48DkAORA5IDkwOUA5UDlgOX
            A5gDmQOaA5sDnAOdA54DnwOgA6H//QOjA6QDpQOmA6cDqAOpA6oDqwOsA60DrgOv
            A7ADsQOyA7MDtAO1A7YDtwO4A7kDugO7A7wDvQO+A78DwAPBA8IDwwPEA8UDxgPH
            A8gDyQPKA8sDzAPNA87//Q==
            """,
            options: .ignoreUnknownCharacters
        )!,
        Data(
            base64Encoded: """
            IKz//SAaAZIgHiAmICAgIQLGIDABYCA5AVL//f/9//3//SAYIBkgHCAdICIgEyAU
            AtwhIgFhIDoBU//9//0BeACgAKEAogCjAKQApQCmAKcAqACpAKoAqwCsAK0ArgCv
            ALAAsQCyALMAtAC1ALYAtwC4ALkAugC7ALwAvQC+AL8AwADBAMIAwwDEAMUAxgDH
            AMgAyQDKAMsAzADNAM4AzwEeANEA0gDTANQA1QDWANcA2ADZANoA2wDcATABXgDf
            AOAA4QDiAOMA5ADlAOYA5wDoAOkA6gDrAOwA7QDuAO8BHwDxAPIA8wD0APUA9gD3
            APgA+QD6APsA/AExAV8A/w==
            """,
            options: .ignoreUnknownCharacters
        )!,
        Data(
            base64Encoded: """
            IKz//SAaAZIgHiAmICAgIQLGIDD//SA5//3//f/9//3//SAYIBkgHCAdICIgEyAU
            AtwhIv/9IDr//f/9//3//QCgAKEAogCjIKoApQCmAKcAqACpANcAqwCsAK0ArgCv
            ALAAsQCyALMAtAC1ALYAtwC4ALkA9wC7ALwAvQC+AL8FsAWxBbIFswW0BbUFtgW3
            BbgFuf/9BbsFvAW9Bb4FvwXABcEFwgXDBfAF8QXyBfMF9P/9//3//f/9//3//f/9
            BdAF0QXSBdMF1AXVBdYF1wXYBdkF2gXbBdwF3QXeBd8F4AXhBeIF4wXkBeUF5gXn
            BegF6QXq//3//SAOIA///Q==
            """,
            options: .ignoreUnknownCharacters
        )!,
        Data(
            base64Encoded: """
            IKwGfiAaAZIgHiAmICAgIQLGIDAGeSA5AVIGhgaYBogGryAYIBkgHCAdICIgEyAU
            BqkhIgaRIDoBUyAMIA0GugCgBgwAogCjAKQApQCmAKcAqACpBr4AqwCsAK0ArgCv
            ALAAsQCyALMAtAC1ALYAtwC4ALkGGwC7ALwAvQC+Bh8GwQYhBiIGIwYkBiUGJgYn
            BigGKQYqBisGLAYtBi4GLwYwBjEGMgYzBjQGNQY2ANcGNwY4BjkGOgZABkEGQgZD
            AOAGRADiBkUGRgZHBkgA5wDoAOkA6gDrBkkGSgDuAO8GSwZMBk0GTgD0Bk8GUAD3
            BlEA+QZSAPsA/CAOIA8G0g==
            """,
            options: .ignoreUnknownCharacters
        )!,
        Data(
            base64Encoded: """
            IKz//SAa//0gHiAmICAgIf/9IDD//SA5//0AqALHALj//SAYIBkgHCAdICIgEyAU
            //0hIv/9IDr//QCvAtv//QCg//0AogCjAKT//QCmAKcA2ACpAVYAqwCsAK0ArgDG
            ALAAsQCyALMAtAC1ALYAtwD4ALkBVwC7ALwAvQC+AOYBBAEuAQABBgDEAMUBGAES
            AQwAyQF5ARYBIgE2ASoBOwFgAUMBRQDTAUwA1QDWANcBcgFBAVoBagDcAXsBfQDf
            AQUBLwEBAQcA5ADlARkBEwENAOkBegEXASMBNwErATwBYQFEAUYA8wFNAPUA9gD3
            AXMBQgFbAWsA/AF8AX4C2Q==
            """,
            options: .ignoreUnknownCharacters
        )!,
        Data(
            base64Encoded: """
            IKz//SAaAZIgHiAmICAgIQLGIDD//SA5AVL//f/9//3//SAYIBkgHCAdICIgEyAU
            AtwhIv/9IDoBU//9//0BeACgAKEAogCjAKQApQCmAKcAqACpAKoAqwCsAK0ArgCv
            ALAAsQCyALMAtAC1ALYAtwC4ALkAugC7ALwAvQC+AL8AwADBAMIBAgDEAMUAxgDH
            AMgAyQDKAMsDAADNAM4AzwEQANEDCQDTANQBoADWANcA2ADZANoA2wDcAa8DAwDf
            AOAA4QDiAQMA5ADlAOYA5wDoAOkA6gDrAwEA7QDuAO8BEQDxAyMA8wD0AaEA9gD3
            APgA+QD6APsA/AGwIKsA/w==
            """,
            options: .ignoreUnknownCharacters
        )!,
        Data(
            base64Encoded: """
            AMQAxQDHAMkA0QDWANwA4QDgAOIA5ADjAOUA5wDpAOgA6gDrAO0A7ADuAO8A8QDz
            APIA9AD2APUA+gD5APsA/CAgALAAogCjAKcgIgC2AN8ArgCpISIAtACoImAAxgDY
            Ih4AsSJkImUApQC1IgIiESIPA8AiKwCqALoDqQDmAPgAvwChAKwiGgGSIkgDlACr
            ALsgJgCgAMAAwyEmAVIBUyATIBQgHCAdIBggGQD3JcoA/wF4IEQApCA5IDr7AfsC
            ICEAtyAaIB4gMADCAMoAwQDLAMgAzQDOAM8AzADTANTgHgDSANoA2wDZATH//f/9
            AK8C2ALZAtoAuALdAtsCxw==
            """,
            options: .ignoreUnknownCharacters
        )!,
        Data(
            base64Encoded: """
            BBAEEQQSBBMEFAQVBBYEFwQYBBkEGgQbBBwEHQQeBB8EIAQhBCIEIwQkBCUEJgQn
            BCgEKQQqBCsELAQtBC4ELwQwBDEEMgQzBDQENQQ2BDcEOAQ5BDoEOwQ8BD0EPgQ/
            JZElkiWTJQIlJCVhJWIlViVVJWMlUSVXJV0lXCVbJRAlFCU0JSwlHCUAJTwlXiVf
            JVolVCVpJWYlYCVQJWwlZyVoJWQlZSVZJVglUiVTJWslaiUYJQwliCWEJYwlkCWA
            BEAEQQRCBEMERARFBEYERwRIBEkESgRLBEwETQROBE8EAQRRBAQEVAQHBFcEDgRe
            ALAiGQC3IhohFgCkJaAAoA==
            """,
            options: .ignoreUnknownCharacters
        )!,
        Data(
            base64Encoded: """
            BBAEEQQSBBMEFAQVBBYEFwQYBBkEGgQbBBwEHQQeBB8EIAQhBCIEIwQkBCUEJgQn
            BCgEKQQqBCsELAQtBC4ELyAgALAEkACjAKcgIgC2BAYArgCpISIEAgRSImAEAwRT
            Ih4AsSJkImUEVgC1BJEECAQEBFQEBwRXBAkEWQQKBFoEWAQFAKwiGgGSIkgiBgCr
            ALsgJgCgBAsEWwQMBFwEVSATIBQgHCAdIBggGQD3IB4EDgReBA8EXyEWBAEEUQRP
            BDAEMQQyBDMENAQ1BDYENwQ4BDkEOgQ7BDwEPQQ+BD8EQARBBEIEQwREBEUERgRH
            BEgESQRKBEsETARNBE4grA==
            """,
            options: .ignoreUnknownCharacters
        )!,
        Data(
            base64Encoded: """
            IKwAgQCCAIMAhCAmAIYAhwCIAIkAigCLAIwAjQCOAI8AkCAYIBkgHCAdICIgEyAU
            AJgAmQCaAJsAnACdAJ4AnwCgDgEOAg4DDgQOBQ4GDgcOCA4JDgoOCw4MDg0ODg4P
            DhAOEQ4SDhMOFA4VDhYOFw4YDhkOGg4bDhwOHQ4eDh8OIA4hDiIOIw4kDiUOJg4n
            DigOKQ4qDisOLA4tDi4OLw4wDjEOMg4zDjQONQ42DjcOOA45Djr//f/9//3//Q4/
            DkAOQQ5CDkMORA5FDkYORw5IDkkOSg5LDkwOTQ5ODk8OUA5RDlIOUw5UDlUOVg5X
            DlgOWQ5aDlv//f/9//3//Q==
            """,
            options: .ignoreUnknownCharacters
        )!,
    ]
}
