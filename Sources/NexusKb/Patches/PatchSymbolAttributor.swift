import Foundation

struct PatchSymbolAttributor: Sendable {
    static let extractorVersion = "patch-symbols/1.0.0"

    func observations(
        in document: PatchDocument
    ) -> [PatchSymbolObservation] {
        var observations: [PatchSymbolObservation] = []

        for (fileIndex, file) in document.files.enumerated() {
            guard let filePath = file.path else {
                continue
            }

            for (hunkIndex, hunk) in file.hunks.enumerated() {
                attribute(
                    hunk,
                    fileIndex: fileIndex,
                    hunkIndex: hunkIndex,
                    filePath: filePath,
                    into: &observations
                )
            }
        }

        return deduplicated(observations)
    }

    private func attribute(
        _ hunk: PatchHunk,
        fileIndex: Int,
        hunkIndex: Int,
        filePath: String,
        into observations: inout [PatchSymbolObservation]
    ) {
        let headerSymbol = hunk.sectionHeader
            .flatMap(symbolFromHunkHeader)
        let changedLines = hunk.lines.filter {
            $0.kind == .addition
                || $0.kind == .deletion
        }

        if let headerSymbol,
            !changedLines.isEmpty
        {
            observations.append(
                observation(
                    headerSymbol,
                    relationship: .modifies,
                    fileIndex: fileIndex,
                    filePath: filePath,
                    hunkIndex: hunkIndex,
                    lineIndex: nil,
                    lineKind: nil,
                    method: .hunkHeader,
                    confidence: 0.98
                )
            )
        }

        let additions = branch(
            for: .addition,
            in: hunk
        )
        let deletions = branch(
            for: .deletion,
            in: hunk
        )

        attribute(
            additions,
            changedKind: .addition,
            definitionRelationship: .adds,
            headerSymbol: headerSymbol,
            fileIndex: fileIndex,
            hunkIndex: hunkIndex,
            filePath: filePath,
            into: &observations
        )
        attribute(
            deletions,
            changedKind: .deletion,
            definitionRelationship: .deletes,
            headerSymbol: headerSymbol,
            fileIndex: fileIndex,
            hunkIndex: hunkIndex,
            filePath: filePath,
            into: &observations
        )
    }

    private struct BranchLine {
        let content: String
        let hunkLineIndex: Int
        let kind: PatchDiffLineKind
    }

    private func branch(
        for changedKind: PatchDiffLineKind,
        in hunk: PatchHunk
    ) -> [BranchLine] {
        hunk.lines.enumerated().compactMap {
            index,
            line in

            guard
                line.kind == .context
                    || line.kind == changedKind
            else {
                return nil
            }

            return BranchLine(
                content: line.content,
                hunkLineIndex: index,
                kind: line.kind
            )
        }
    }

    private func attribute(
        _ branch: [BranchLine],
        changedKind: PatchDiffLineKind,
        definitionRelationship:
            PatchSymbolRelationship,
        headerSymbol: PatchSymbol?,
        fileIndex: Int,
        hunkIndex: Int,
        filePath: String,
        into observations:
            inout [PatchSymbolObservation]
    ) {
        for index in branch.indices
        where branch[index].kind == changedKind {
            let line = branch[index]
            let definition = definition(
                at: index,
                in: branch
            )

            if let definition {
                observations.append(
                    observation(
                        definition,
                        relationship:
                            definitionRelationship,
                        fileIndex: fileIndex,
                        filePath: filePath,
                        hunkIndex: hunkIndex,
                        lineIndex: line.hunkLineIndex,
                        lineKind: changedKind,
                        method: .changedLineDefinition,
                        confidence: 0.96
                    )
                )
            } else if let walkedBack = walkBack(
                from: index,
                in: branch
            ), walkedBack != headerSymbol {
                observations.append(
                    observation(
                        walkedBack,
                        relationship: .modifies,
                        fileIndex: fileIndex,
                        filePath: filePath,
                        hunkIndex: hunkIndex,
                        lineIndex: line.hunkLineIndex,
                        lineKind: changedKind,
                        method: .walkback,
                        confidence: 0.82
                    )
                )
            }

            let calls = callSymbols(
                in: line.content,
                excluding: definition
            )

            for symbol in calls {
                observations.append(
                    observation(
                        symbol,
                        relationship: .calls,
                        fileIndex: fileIndex,
                        filePath: filePath,
                        hunkIndex: hunkIndex,
                        lineIndex: line.hunkLineIndex,
                        lineKind: changedKind,
                        method: .changedLineCall,
                        confidence: 0.86
                    )
                )
            }

            for symbol in mentionSymbols(
                in: line.content,
                excluding: Set(calls + [definition].compactMap { $0 })
            ) {
                observations.append(
                    observation(
                        symbol,
                        relationship: .mentions,
                        fileIndex: fileIndex,
                        filePath: filePath,
                        hunkIndex: hunkIndex,
                        lineIndex: line.hunkLineIndex,
                        lineKind: changedKind,
                        method: .changedLineMention,
                        confidence: 0.68
                    )
                )
            }
        }
    }

    private func walkBack(
        from changedIndex: Int,
        in lines: [BranchLine]
    ) -> PatchSymbol? {
        let lowerBound = max(0, changedIndex - 50)

        for index in stride(
            from: changedIndex,
            through: lowerBound,
            by: -1
        ) {
            if let symbol = definition(
                at: index,
                in: lines
            ) {
                return symbol
            }
        }

        return nil
    }

    private func definition(
        at index: Int,
        in lines: [BranchLine]
    ) -> PatchSymbol? {
        let line = lines[index].content
        let trimmed = line.trimmingCharacters(
            in: .whitespaces
        )

        if trimmed.hasPrefix("#define ") {
            return macroSymbol(in: trimmed)
        }

        if let type = typeSymbol(
            in: trimmed,
            requiresDefinition: true
        ) {
            return type
        }

        guard line.first?.isWhitespace == false,
            !trimmed.hasPrefix("//"),
            !trimmed.hasPrefix("/*"),
            !trimmed.hasPrefix("*"),
            !trimmed.hasPrefix("#"),
            let function = functionSymbol(in: trimmed),
            hasDefinitionBrace(
                at: index,
                in: lines
            )
        else {
            return nil
        }

        return function
    }

    private func hasDefinitionBrace(
        at index: Int,
        in lines: [BranchLine]
    ) -> Bool {
        if lines[index].content.contains("{") {
            return true
        }

        let end = min(lines.count, index + 20)

        guard index + 1 < end else {
            return false
        }

        for nextIndex in (index + 1)..<end {
            let line = lines[nextIndex].content
            let trimmed = line.trimmingCharacters(
                in: .whitespaces
            )

            if trimmed.hasPrefix("{") {
                return true
            }

            if trimmed.isEmpty
                || line.first?.isWhitespace == true
                || trimmed.hasSuffix(",")
                || trimmed.hasSuffix("(")
                || trimmed.hasSuffix(")")
            {
                continue
            }

            return false
        }

        return false
    }

    private func symbolFromHunkHeader(
        _ header: String
    ) -> PatchSymbol? {
        let trimmed = header.trimmingCharacters(
            in: .whitespaces
        )

        return macroSymbol(in: trimmed)
            ?? functionSymbol(in: trimmed)
            ?? typeSymbol(
                in: trimmed,
                requiresDefinition: false
            )
    }

    private func functionSymbol(
        in line: String
    ) -> PatchSymbol? {
        guard let parenthesis = line.firstIndex(of: "(")
        else {
            return nil
        }

        let before = line[..<parenthesis]
        let name = before.split {
            !$0.isLetter
                && !$0.isNumber
                && $0 != "_"
        }.last.map(String.init)

        guard let name,
            isIdentifier(name),
            !Self.nonCallKeywords.contains(name)
        else {
            return nil
        }

        return PatchSymbol(
            name: name,
            kind: name.allSatisfy({
                !$0.isLetter || $0.isUppercase
            }) ? .macro : .function
        )
    }

    private func macroSymbol(
        in line: String
    ) -> PatchSymbol? {
        guard line.hasPrefix("#define ") else {
            return nil
        }

        let remainder = line.dropFirst(
            "#define ".count
        )
        let name = remainder.prefix {
            $0.isLetter
                || $0.isNumber
                || $0 == "_"
        }

        guard isIdentifier(String(name)) else {
            return nil
        }

        return PatchSymbol(
            name: String(name),
            kind: .macro
        )
    }

    private func typeSymbol(
        in line: String,
        requiresDefinition: Bool
    ) -> PatchSymbol? {
        if requiresDefinition,
            !line.contains("{")
        {
            return nil
        }

        let words = identifiers(in: line)
        let typeKeywords = ["struct", "union", "enum"]
        let keywordIndex = words.first == "typedef" ? 1 : 0

        guard words.indices.contains(keywordIndex),
            words.indices.contains(keywordIndex + 1),
            typeKeywords.contains(words[keywordIndex])
        else {
            return nil
        }

        if let parenthesis = line.firstIndex(of: "(") {
            guard let brace = line.firstIndex(of: "{"),
                brace < parenthesis
            else {
                return nil
            }
        }

        let keyword = words[keywordIndex]
        let name = words[keywordIndex + 1]

        guard isIdentifier(name) else {
            return nil
        }

        return PatchSymbol(
            name: "\(keyword) \(name)",
            kind: .type
        )
    }

    private func callSymbols(
        in line: String,
        excluding definition: PatchSymbol?
    ) -> [PatchSymbol] {
        var symbols: [PatchSymbol] = []
        var index = line.startIndex

        while index < line.endIndex {
            guard line[index] == "(" else {
                index = line.index(after: index)
                continue
            }

            let end = index
            var start = end

            while start > line.startIndex {
                let previous = line.index(before: start)
                let character = line[previous]

                guard
                    character.isLetter
                        || character.isNumber
                        || character == "_"
                else {
                    break
                }

                start = previous
            }

            let name = String(line[start..<end])

            if isIdentifier(name),
                !Self.nonCallKeywords.contains(name),
                name != definition?.name
            {
                symbols.append(
                    PatchSymbol(
                        name: name,
                        kind: name.allSatisfy({
                            !$0.isLetter
                                || $0.isUppercase
                        }) ? .macro : .function
                    )
                )
            }

            index = line.index(after: index)
        }

        return symbols
    }

    private func mentionSymbols(
        in line: String,
        excluding excluded: Set<PatchSymbol>
    ) -> [PatchSymbol] {
        var symbols: [PatchSymbol] = []
        let words = identifiers(in: line)

        for (index, word) in words.enumerated() {
            if ["struct", "union", "enum"].contains(word),
                words.indices.contains(index + 1)
            {
                let symbol = PatchSymbol(
                    name: "\(word) \(words[index + 1])",
                    kind: .type
                )

                if !excluded.contains(symbol) {
                    symbols.append(symbol)
                }
            }

            let isUppercaseName =
                word.contains(
                    where: \.isLetter
                )
                && word.allSatisfy {
                    !$0.isLetter || $0.isUppercase
                }

            if isUppercaseName,
                word.count > 1
            {
                let symbol = PatchSymbol(
                    name: word,
                    kind: .macro
                )

                if !excluded.contains(symbol) {
                    symbols.append(symbol)
                }
            }
        }

        return symbols
    }

    private func identifiers(
        in line: String
    ) -> [String] {
        line.split {
            !$0.isLetter
                && !$0.isNumber
                && $0 != "_"
        }.map(String.init)
    }

    private func isIdentifier(
        _ value: String
    ) -> Bool {
        guard let first = value.first,
            first.isLetter || first == "_"
        else {
            return false
        }

        return value.dropFirst().allSatisfy {
            $0.isLetter
                || $0.isNumber
                || $0 == "_"
        }
    }

    private func observation(
        _ symbol: PatchSymbol,
        relationship: PatchSymbolRelationship,
        fileIndex: Int,
        filePath: String,
        hunkIndex: Int,
        lineIndex: Int?,
        lineKind: PatchDiffLineKind?,
        method: PatchSymbolEvidenceMethod,
        confidence: Double
    ) -> PatchSymbolObservation {
        PatchSymbolObservation(
            symbol: symbol,
            relationship: relationship,
            fileIndex: fileIndex,
            filePath: filePath,
            hunkIndex: hunkIndex,
            lineIndex: lineIndex,
            lineKind: lineKind,
            evidenceMethod: method,
            confidence: confidence,
            extractorVersion: Self.extractorVersion
        )
    }

    private func deduplicated(
        _ observations: [PatchSymbolObservation]
    ) -> [PatchSymbolObservation] {
        var seen = Set<String>()

        return observations.filter {
            let key = [
                String($0.fileIndex),
                String($0.hunkIndex),
                $0.symbol.kind.rawValue,
                $0.symbol.name,
                $0.relationship.rawValue,
                $0.evidenceMethod.rawValue,
                $0.lineIndex.map(String.init) ?? "",
                $0.lineKind?.rawValue ?? "",
            ].joined(separator: "\u{1f}")

            return seen.insert(key).inserted
        }
    }

    private static let nonCallKeywords: Set<String> = [
        "if",
        "else",
        "for",
        "while",
        "do",
        "switch",
        "case",
        "return",
        "sizeof",
        "typeof",
        "alignof",
        "defined",
    ]
}
