import Foundation
import Testing
@testable import NexusKb

@Test
func parsesCommitMessageTrailersAndNormalDiff() throws {
    let source = try patchFixture("normal")
    let document = try PatchDocumentParser().parse(
        source
    )

    #expect(document.rawText == source)
    #expect(document.quotePrefix == nil)
    #expect(
        document.commitMessage
            == """
            net: sample: handle worker startup failure

            Return the helper error instead of discarding it.
            """
    )
    #expect(
        document.trailers.map(\.key)
            == ["Fixes", "Signed-off-by"]
    )
    #expect(document.diffPreamble.first == "---")
    #expect(document.files.count == 1)

    let file = try #require(document.files.first)
    #expect(file.oldPath == "drivers/net/sample.c")
    #expect(file.newPath == "drivers/net/sample.c")
    #expect(file.operation == .modified)
    #expect(file.hunks.count == 1)

    let hunk = try #require(file.hunks.first)
    #expect(hunk.oldRange == PatchLineRange(start: 10, count: 3))
    #expect(hunk.newRange == PatchLineRange(start: 10, count: 4))
    #expect(
        hunk.sectionHeader
            == "static int worker_start(struct device *dev)"
    )
    #expect(
        hunk.lines.map(\.kind) == [
            .context,
            .deletion,
            .addition,
            .addition,
            .context,
        ]
    )
    #expect(hunk.lines[1].oldLineNumber == 11)
    #expect(hunk.lines[1].newLineNumber == nil)
    #expect(hunk.lines[2].oldLineNumber == nil)
    #expect(hunk.lines[2].newLineNumber == 11)
    #expect(document.trailingLines == ["-- ", "2.47.0"])
}

@Test
func parsesQuotedTraditionalDiff() throws {
    let document = try PatchDocumentParser().parse(
        patchFixture("quoted")
    )

    #expect(document.quotePrefix == "> ")
    #expect(
        document.commitMessage.hasPrefix(
            "fs: sample: quoted review copy"
        )
    )
    #expect(
        document.trailers.map(\.key)
            == ["Signed-off-by"]
    )

    let file = try #require(document.files.first)
    #expect(file.diffHeader == "--- a/fs/sample.c")
    #expect(file.oldPath == "fs/sample.c")
    #expect(file.newPath == "fs/sample.c")
    #expect(file.operation == .modified)
    #expect(file.hunks.first?.lines.count == 3)
}

@Test
func parsesRenameAddAndDeleteOperations() throws {
    let rename = try PatchDocumentParser().parse(
        patchFixture("renamed")
    )
    let renamedFile = try #require(rename.files.first)

    #expect(renamedFile.operation == .renamed)
    #expect(
        renamedFile.oldPath
            == "Documentation/core-api/old-name.rst"
    )
    #expect(
        renamedFile.newPath
            == "Documentation/core-api/new-name.rst"
    )
    #expect(renamedFile.hunks.isEmpty)

    let replacement = try PatchDocumentParser().parse(
        patchFixture("added-deleted")
    )

    #expect(replacement.files.count == 2)
    #expect(replacement.files[0].operation == .deleted)
    #expect(replacement.files[0].newPath == nil)
    #expect(
        replacement.files[0].hunks[0]
            .lines.last?.kind == .noNewlineMarker
    )
    #expect(replacement.files[1].operation == .added)
    #expect(replacement.files[1].oldPath == nil)
    #expect(
        replacement.files[1].hunks[0]
            .lines.last?.kind == .noNewlineMarker
    )
}

@Test
func parsesMacroTypeAndMultiHunkCorpus() throws {
    let macroType = try PatchDocumentParser().parse(
        patchFixture("macro-type")
    )
    let multiHunk = try PatchDocumentParser().parse(
        patchFixture("multi-hunk")
    )

    #expect(macroType.files.first?.hunks.count == 2)
    #expect(multiHunk.files.first?.hunks.count == 2)
    #expect(
        multiHunk.files.first?.hunks[1]
            .sectionHeader == nil
    )
    #expect(
        multiHunk.files.first?.hunks[1]
            .oldRange
            == PatchLineRange(start: 20, count: 4)
    )
}

@Test
func rejectsMalformedHunkCounts() throws {
    let source = try patchFixture("malformed")

    #expect(
        throws: PatchDocumentParserError
            .hunkLineCountMismatch(
                header:
                    "@@ -1,2 +1,2 @@ static int broken(void)",
                expectedOld: 2,
                actualOld: 1,
                expectedNew: 2,
                actualNew: 1
            )
    ) {
        try PatchDocumentParser().parse(source)
    }
}

@Test
func recoversTransportStrippedContextMarkers() throws {
    let source = """
        transport-normalized context

        ---
        diff --git a/kernel/sample.c b/kernel/sample.c
        --- a/kernel/sample.c
        +++ b/kernel/sample.c
        @@ -1,4 +1,4 @@ int sample(void)
        int sample(void)
         {
        -\treturn old_value();
        +\treturn new_value();
         }
        """
    let document = try PatchDocumentParser().parse(
        source
    )
    let lines = try #require(
        document.files.first?.hunks.first?.lines
    )

    #expect(lines.first?.kind == .context)
    #expect(lines.first?.content == "int sample(void)")
    #expect(lines.first?.rawText == "int sample(void)")
    #expect(lines.first?.isInferred == true)
    #expect(
        lines.dropFirst().allSatisfy {
            !$0.isInferred
        }
    )
}

private func patchFixture(
    _ name: String
) throws -> String {
    let directory = try #require(
        Bundle.module.url(
            forResource: "Patches",
            withExtension: nil,
            subdirectory: "Fixtures"
        )
    )
    let url = directory.appendingPathComponent(
        "\(name).patch"
    )

    return try String(
        contentsOf: url,
        encoding: .utf8
    )
}
