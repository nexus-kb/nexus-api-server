import Foundation
import Testing
@testable import NexusKb

@Test
func attributesHeaderSymbolsAndChangedCalls() throws {
    let observations = try observations(
        for: "normal"
    )

    #expect(
        observations.contains {
            $0.symbol
                == PatchSymbol(
                    name: "worker_start",
                    kind: .function
                )
            && $0.relationship == .modifies
            && $0.evidenceMethod == .hunkHeader
            && $0.confidence == 0.98
        }
    )
    #expect(
        observations.contains {
            $0.symbol.name == "old_helper"
            && $0.relationship == .calls
            && $0.lineKind == .deletion
        }
    )
    #expect(
        observations.contains {
            $0.symbol.name == "new_helper"
            && $0.relationship == .calls
            && $0.lineKind == .addition
        }
    )
    #expect(
        observations.allSatisfy {
            $0.extractorVersion
                == PatchSymbolAttributor.extractorVersion
        }
    )
}

@Test
func keepsAddedAndDeletedDefinitionsDistinct() throws {
    let observations = try observations(
        for: "added-deleted"
    )

    #expect(
        observations.contains {
            $0.symbol.name == "legacy_helper"
            && $0.relationship == .deletes
            && $0.evidenceMethod
                == .changedLineDefinition
        }
    )
    #expect(
        observations.contains {
            $0.symbol.name == "current_helper"
            && $0.relationship == .adds
            && $0.evidenceMethod
                == .changedLineDefinition
        }
    )
}

@Test
func attributesMacrosTypesAndMentionsSeparately() throws {
    let observations = try observations(
        for: "macro-type"
    )

    #expect(
        observations.contains {
            $0.symbol
                == PatchSymbol(
                    name: "SAMPLE_LIMIT",
                    kind: .macro
                )
            && $0.relationship == .adds
        }
    )
    #expect(
        observations.contains {
            $0.symbol.name == "SAMPLE_LIMIT"
            && $0.relationship == .deletes
        }
    )
    #expect(
        observations.contains {
            $0.symbol
                == PatchSymbol(
                    name: "struct device_state",
                    kind: .type
                )
            && $0.relationship == .modifies
            && $0.evidenceMethod == .hunkHeader
        }
    )
    #expect(
        observations.contains {
            $0.symbol
                == PatchSymbol(
                    name: "enum sample_mode",
                    kind: .type
                )
            && $0.relationship == .mentions
            && $0.lineKind == .addition
        }
    )
}

@Test
func fallsBackToWalkbackWhenHunkHeaderHasNoSymbol() throws {
    let observations = try observations(
        for: "multi-hunk"
    )

    #expect(
        observations.contains {
            $0.symbol.name == "first_worker"
            && $0.relationship == .modifies
            && $0.evidenceMethod == .hunkHeader
        }
    )
    #expect(
        observations.contains {
            $0.symbol.name == "second_worker"
            && $0.relationship == .modifies
            && $0.evidenceMethod == .walkback
        }
    )
    #expect(
        observations.contains {
            $0.symbol.name == "new_second"
            && $0.relationship == .calls
            && $0.lineKind == .addition
        }
    )
}

private func observations(
    for fixture: String
) throws -> [PatchSymbolObservation] {
    let directory = try #require(
        Bundle.module.url(
            forResource: "Patches",
            withExtension: nil,
            subdirectory: "Fixtures"
        )
    )
    let url = directory.appendingPathComponent(
        "\(fixture).patch"
    )
    let source = try String(
        contentsOf: url,
        encoding: .utf8
    )
    let document = try PatchDocumentParser().parse(
        source
    )

    return PatchSymbolAttributor().observations(
        in: document
    )
}
