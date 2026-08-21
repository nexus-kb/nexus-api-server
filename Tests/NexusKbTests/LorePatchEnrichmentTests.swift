import Foundation
import Testing
@testable import NexusKb

@Test
func enrichesRepresentativeLorePatchEmailsEndToEnd() throws {
    for testCase in lorePatchEmailCases {
        let context = "\(testCase.fixture) at \(testCase.sourceCommit)"
        let data = try Data(
            contentsOf: lorePatchEmailFixture(
                testCase.fixture
            )
        )
        let message = try IngestMessageParser().parse(
            data
        )

        #expect(
            message.message.messageID
                == testCase.messageID,
            "\(context): message ID"
        )
        #expect(
            message.message.subject
                == testCase.subject,
            "\(context): subject"
        )
        #expect(
            message.patch.isPatchOrCover,
            "\(context): patch detection"
        )

        let diff = try #require(
            message.patch.diff,
            "\(context): decoded patch body"
        )
        let document = try PatchDocumentParser().parse(
            diff
        )

        #expect(
            document.rawText == diff,
            "\(context): lossless decoded body"
        )
        #expect(
            document.files.count
                == testCase.fileCount,
            "\(context): changed files"
        )
        #expect(
            document.files
                .flatMap(\.hunks)
                .count == testCase.hunkCount,
            "\(context): hunks"
        )
        #expect(
            document.files.map(\.operation)
                == testCase.operations,
            "\(context): file operations"
        )

        let inferredLines = document.files
            .flatMap(\.hunks)
            .flatMap(\.lines)
            .filter(\.isInferred)

        #expect(
            inferredLines.isEmpty,
            "\(context): canonical context markers"
        )

        let observations = PatchSymbolAttributor()
            .observations(in: document)

        if testCase.expectsSymbolObservations {
            #expect(
                !observations.isEmpty,
                "\(context): symbol observations"
            )
        }

        #expect(
            observations.allSatisfy {
                $0.extractorVersion
                    == PatchSymbolAttributor
                        .extractorVersion
                && (0...1).contains($0.confidence)
            },
            "\(context): evidence metadata"
        )
    }
}

private struct LorePatchEmailCase {
    let fixture: String
    let sourceCommit: String
    let messageID: String
    let subject: String
    let fileCount: Int
    let hunkCount: Int
    let operations: [PatchFileOperation]
    let expectsSymbolObservations: Bool
}

private let lorePatchEmailCases: [
    LorePatchEmailCase
] = [
    LorePatchEmailCase(
        fixture: "sch-cake-8bit.eml",
        sourceCommit:
            "ec5a5656f4ad04df6a8eec039393fc204cf8f42c",
        messageID:
            "20260820154503.892214-1-ooonea@gmail.com",
        subject:
            "[PATCH net v3] net/sched: sch_cake: fix autorate reconfiguration throttling",
        fileCount: 1,
        hunkCount: 1,
        operations: [.modified],
        expectsSymbolObservations: true
    ),
    LorePatchEmailCase(
        fixture: "exfat-multi-file.eml",
        sourceCommit:
            "4428ad913db5b3b4201c90eaba693f1ac412d170",
        messageID:
            "20260820150508.736275-1-anmuxixixi@gmail.com",
        subject:
            "[PATCH] exfat: validate vendor allocation directory entries",
        fileCount: 2,
        hunkCount: 3,
        operations: [.modified, .modified],
        expectsSymbolObservations: true
    ),
    LorePatchEmailCase(
        fixture: "dt-bindings-add-delete.eml",
        sourceCommit:
            "db81efa64c7eff2a9a30cd5ecef0432d268e72de",
        messageID:
            "20260820150223.108374-1-challauday369@gmail.com",
        subject:
            "[PATCH] dt-bindings: leds: lacie,netxbig-leds: Convert to DT schema",
        fileCount: 2,
        hunkCount: 2,
        operations: [.added, .deleted],
        expectsSymbolObservations: false
    ),
    LorePatchEmailCase(
        fixture: "hwmon-multi-hunk.eml",
        sourceCommit:
            "525619619b5c9705134640aac01522ae2840f466",
        messageID:
            "20260820145946.35468-3-alessandro.zini@siemens.com",
        subject:
            "[PATCH 2/2] hwmon: (sht4x): Add support for Sensirion STS4x temperature sensors",
        fileCount: 2,
        hunkCount: 12,
        operations: [.modified, .modified],
        expectsSymbolObservations: true
    ),
    LorePatchEmailCase(
        fixture: "geni-seven-bit.eml",
        sourceCommit:
            "317bf24cceb82db8f5901947f2692e848bcdc8c0",
        messageID:
            "20260820-fix-write-to-read-only-firmware-buffer-v2-4-7badcdc455fe@oss.qualcomm.com",
        subject:
            "[PATCH v2 4/4] soc: qcom: geni-se: Fix write to read-only firmware buffer",
        fileCount: 1,
        hunkCount: 4,
        operations: [.modified],
        expectsSymbolObservations: true
    ),
    LorePatchEmailCase(
        fixture: "bpf-new-files.eml",
        sourceCommit:
            "3085bafda593922d2d819a6e779f5672a74aa4c0",
        messageID:
            "20260820131801.68759-4-tasos.papagiannnis@gmail.com",
        subject:
            "[PATCH bpf-next v2 3/3] selftests/bpf: Test linux_binprm user memory kfuncs",
        fileCount: 2,
        hunkCount: 2,
        operations: [.added, .added],
        expectsSymbolObservations: true
    ),
    LorePatchEmailCase(
        fixture: "rust-source.eml",
        sourceCommit:
            "9337dad7b5c48b1fe56a44c7511b0bdae6839ea9",
        messageID:
            "20260820135733.37121-1-gary@kernel.org",
        subject:
            "[PATCH] rust: cfi: disable function merging if CFI is enabled",
        fileCount: 1,
        hunkCount: 1,
        operations: [.modified],
        expectsSymbolObservations: false
    ),
    LorePatchEmailCase(
        fixture: "docs-source.eml",
        sourceCommit:
            "7c71a63d38f2e72dc8c3713ef4f864bc717f5c56",
        messageID:
            "20260820144655.22492-1-haohlliang@gmail.com",
        subject:
            "[PATCH v5] docs: real-time: mention the hrtimer sleeper HARD path",
        fileCount: 1,
        hunkCount: 1,
        operations: [.modified],
        expectsSymbolObservations: false
    ),
    LorePatchEmailCase(
        fixture: "mt76-quoted-printable.eml",
        sourceCommit:
            "5361ee67e5e2606ca15067c42e9edb85fb3b60fc",
        messageID:
            "20260820-mt7915-wcid-publish-order-v1-1-79d2bc981d8b@protonmail.com",
        subject:
            "[PATCH mt76] wifi: mt76: mt7915: publish wcid before MCU add commands",
        fileCount: 1,
        hunkCount: 1,
        operations: [.modified],
        expectsSymbolObservations: true
    ),
    LorePatchEmailCase(
        fixture: "xhci-base64.eml",
        sourceCommit:
            "f1a02125f914895026ef7e8113b3c5892f672025",
        messageID:
            "20260818-xhci-pci-prom21-v1-1-6584857e654d@outlook.com.au",
        subject:
            "[PATCH] usb: xhci-pci: Add AMD 600 series to xhci-pci-prom21",
        fileCount: 3,
        hunkCount: 3,
        operations: [
            .modified,
            .modified,
            .modified,
        ],
        expectsSymbolObservations: true
    ),
    LorePatchEmailCase(
        fixture: "phy-rename.eml",
        sourceCommit:
            "25142e0875771be918dc8d6a9301cc413cfd5c38",
        messageID:
            "20260818095355.18898-1-ansuelsmth@gmail.com",
        subject:
            "[PATCH] phy: move and rename Airoha PCIe PHY driver to dedicated directory",
        fileCount: 7,
        hunkCount: 9,
        operations: [
            .modified,
            .modified,
            .modified,
            .added,
            .added,
            .renamed,
            .renamed,
        ],
        expectsSymbolObservations: true
    ),
]

private func lorePatchEmailFixture(
    _ name: String
) throws -> URL {
    try #require(
        Bundle.module.url(
            forResource: name,
            withExtension: nil,
            subdirectory:
                "Fixtures/LorePatchEmails"
        )
    )
}
