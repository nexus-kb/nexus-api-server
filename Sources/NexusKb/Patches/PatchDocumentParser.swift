import Foundation

enum PatchDocumentParserError:
    Error,
    Sendable,
    Equatable
{
    case noDiff
    case malformedFileHeader(line: String)
    case malformedHunkHeader(line: String)
    case invalidHunkLine(line: String)
    case hunkLineCountMismatch(
        header: String,
        expectedOld: Int,
        actualOld: Int,
        expectedNew: Int,
        actualNew: Int
    )
}

struct PatchDocumentParser: Sendable {
    func parse(
        _ rawText: String
    ) throws -> PatchDocument {
        let rawLines = splitLines(rawText)
        let quote = quoteInformation(in: rawLines)
        let lines = rawLines.map {
            removeQuotePrefix(
                from: $0,
                depth: quote.depth
            )
        }

        guard let diffStart = firstDiffLine(in: lines)
        else {
            throw PatchDocumentParserError.noDiff
        }

        let separator: Int?

        if diffStart > 0 {
            separator = stride(
                from: diffStart - 1,
                through: 0,
                by: -1
            ).first {
                lines[$0].trimmingCharacters(
                    in: .whitespaces
                ) == "---"
            }
        } else {
            separator = nil
        }

        let messageEnd = separator ?? diffStart
        let messageAndTrailers = parseMessageAndTrailers(
            Array(lines[..<messageEnd])
        )
        let preambleStart = separator ?? diffStart
        let preamble = Array(
            lines[preambleStart..<diffStart]
        )
        var files = try parseFiles(
            Array(lines[diffStart...])
        )
        var trailingLines: [String] = []

        if let last = files.last,
            !last.hunks.isEmpty,
            !last.trailingLines.isEmpty
        {
            trailingLines = last.trailingLines
            files[files.count - 1] = PatchChangedFile(
                oldPath: last.oldPath,
                newPath: last.newPath,
                operation: last.operation,
                diffHeader: last.diffHeader,
                headerLines: last.headerLines,
                hunks: last.hunks,
                trailingLines: []
            )
        }

        return PatchDocument(
            rawText: rawText,
            quotePrefix: quote.prefix,
            commitMessage: messageAndTrailers.message,
            trailers: messageAndTrailers.trailers,
            diffPreamble: preamble,
            files: files,
            trailingLines: trailingLines
        )
    }

    private func splitLines(
        _ text: String
    ) -> [String] {
        var lines = text.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map(String.init)

        if text.hasSuffix("\n") {
            lines.removeLast()
        }

        return lines.map {
            $0.hasSuffix("\r")
                ? String($0.dropLast())
                : $0
        }
    }

    private func quoteInformation(
        in lines: [String]
    ) -> (prefix: String?, depth: Int) {
        for index in lines.indices {
            let information = leadingQuote(
                in: lines[index]
            )

            guard information.depth > 0 else {
                continue
            }

            if isDiffStart(information.content) {
                return (
                    information.prefix,
                    information.depth
                )
            }

            if information.content.hasPrefix("--- "),
                lines.indices.contains(index + 1)
            {
                let next = leadingQuote(
                    in: lines[index + 1]
                )

                if next.depth == information.depth,
                    next.content.hasPrefix("+++ ")
                {
                    return (
                        information.prefix,
                        information.depth
                    )
                }
            }
        }

        return (nil, 0)
    }

    private func leadingQuote(
        in line: String
    ) -> (
        prefix: String,
        depth: Int,
        content: String
    ) {
        var index = line.startIndex
        var depth = 0

        while index < line.endIndex,
            line[index] == ">"
        {
            depth += 1
            index = line.index(after: index)

            if index < line.endIndex,
                line[index] == " "
            {
                index = line.index(after: index)
            }
        }

        return (
            String(line[..<index]),
            depth,
            String(line[index...])
        )
    }

    private func removeQuotePrefix(
        from line: String,
        depth: Int
    ) -> String {
        guard depth > 0 else {
            return line
        }

        let information = leadingQuote(in: line)

        guard information.depth >= depth else {
            return line
        }

        var index = line.startIndex

        for _ in 0..<depth {
            index = line.index(after: index)

            if index < line.endIndex,
                line[index] == " "
            {
                index = line.index(after: index)
            }
        }

        return String(line[index...])
    }

    private func firstDiffLine(
        in lines: [String]
    ) -> Int? {
        for index in lines.indices {
            if isDiffStart(lines[index]) {
                return index
            }

            if lines[index].hasPrefix("--- "),
                lines.indices.contains(index + 1),
                lines[index + 1].hasPrefix("+++ ")
            {
                return index
            }
        }

        return nil
    }

    private func isDiffStart(
        _ line: String
    ) -> Bool {
        line.hasPrefix("diff --git ")
    }

    private func parseMessageAndTrailers(
        _ inputLines: [String]
    ) -> (
        message: String,
        trailers: [PatchTrailer]
    ) {
        var lines = inputLines

        while lines.last?.isEmpty == true {
            lines.removeLast()
        }

        var trailerStart = lines.count

        while trailerStart > 0,
            parseTrailer(lines[trailerStart - 1]) != nil
        {
            trailerStart -= 1
        }

        let hasTrailerBoundary =
            trailerStart == 0
            || lines[trailerStart - 1].isEmpty

        guard trailerStart < lines.count,
            hasTrailerBoundary
        else {
            return (lines.joined(separator: "\n"), [])
        }

        let trailers = lines[trailerStart...]
            .compactMap(parseTrailer)
        var messageLines = Array(lines[..<trailerStart])

        while messageLines.last?.isEmpty == true {
            messageLines.removeLast()
        }

        return (
            messageLines.joined(separator: "\n"),
            trailers
        )
    }

    private func parseTrailer(
        _ line: String
    ) -> PatchTrailer? {
        guard let separator = line.firstIndex(of: ":")
        else {
            return nil
        }

        let key = String(line[..<separator])
        let valueStart = line.index(after: separator)
        let value = line[valueStart...]
            .trimmingCharacters(in: .whitespaces)

        guard !key.isEmpty,
            !value.isEmpty,
            key.allSatisfy({
                $0.isLetter
                    || $0.isNumber
                    || $0 == "-"
            })
        else {
            return nil
        }

        return PatchTrailer(
            key: key,
            value: value,
            rawLine: line
        )
    }

    private func parseFiles(
        _ lines: [String]
    ) throws -> [PatchChangedFile] {
        var files: [PatchChangedFile] = []
        var index = 0

        while index < lines.count {
            if isDiffStart(lines[index]) {
                let end =
                    nextFileStart(
                        in: lines,
                        after: index
                    ) ?? lines.count
                files.append(
                    try parseGitFile(
                        Array(lines[index..<end])
                    )
                )
                index = end
                continue
            }

            if lines[index].hasPrefix("--- "),
                lines.indices.contains(index + 1),
                lines[index + 1].hasPrefix("+++ ")
            {
                let end =
                    nextFileStart(
                        in: lines,
                        after: index
                    ) ?? lines.count
                files.append(
                    try parseTraditionalFile(
                        Array(lines[index..<end])
                    )
                )
                index = end
                continue
            }

            index += 1
        }

        guard !files.isEmpty else {
            throw PatchDocumentParserError.noDiff
        }

        return files
    }

    private func nextFileStart(
        in lines: [String],
        after start: Int
    ) -> Int? {
        guard start + 1 < lines.count else {
            return nil
        }

        for index in (start + 1)..<lines.count {
            if isDiffStart(lines[index]) {
                return index
            }

            if lines[index].hasPrefix("--- "),
                lines.indices.contains(index + 1),
                lines[index + 1].hasPrefix("+++ "),
                !lines[start].hasPrefix("diff --git ")
            {
                return index
            }
        }

        return nil
    }

    private func parseGitFile(
        _ lines: [String]
    ) throws -> PatchChangedFile {
        guard let header = lines.first else {
            throw
                PatchDocumentParserError
                .malformedFileHeader(line: "")
        }

        let paths = splitHeaderWords(header)

        guard paths.count >= 4 else {
            throw
                PatchDocumentParserError
                .malformedFileHeader(line: header)
        }

        return try parseFile(
            lines,
            defaultOldPath: normalizedPath(paths[2]),
            defaultNewPath: normalizedPath(paths[3]),
            diffHeader: header
        )
    }

    private func parseTraditionalFile(
        _ lines: [String]
    ) throws -> PatchChangedFile {
        guard lines.count >= 2 else {
            throw
                PatchDocumentParserError
                .malformedFileHeader(
                    line: lines.first ?? ""
                )
        }

        return try parseFile(
            lines,
            defaultOldPath: path(in: lines[0]),
            defaultNewPath: path(in: lines[1]),
            diffHeader: lines[0]
        )
    }

    private func parseFile(
        _ lines: [String],
        defaultOldPath: String?,
        defaultNewPath: String?,
        diffHeader: String
    ) throws -> PatchChangedFile {
        var oldPath = defaultOldPath
        var newPath = defaultNewPath
        var operation: PatchFileOperation = .modified
        var headerLines: [String] = []
        var hunks: [PatchHunk] = []
        var trailingLines: [String] = []
        var index = 0
        var sawHunk = false

        while index < lines.count {
            let line = lines[index]

            if line.hasPrefix("@@ ") {
                sawHunk = true
                let result = try parseHunk(
                    in: lines,
                    at: index
                )
                hunks.append(result.hunk)
                index = result.nextIndex
                continue
            }

            if sawHunk {
                trailingLines.append(line)
            } else {
                headerLines.append(line)

                if line.hasPrefix("--- ") {
                    oldPath = path(in: line)
                } else if line.hasPrefix("+++ ") {
                    newPath = path(in: line)
                } else if line.hasPrefix("rename from ") {
                    oldPath = String(
                        line.dropFirst("rename from ".count)
                    )
                    operation = .renamed
                } else if line.hasPrefix("rename to ") {
                    newPath = String(
                        line.dropFirst("rename to ".count)
                    )
                    operation = .renamed
                } else if line.hasPrefix("copy from ") {
                    oldPath = String(
                        line.dropFirst("copy from ".count)
                    )
                    operation = .copied
                } else if line.hasPrefix("copy to ") {
                    newPath = String(
                        line.dropFirst("copy to ".count)
                    )
                    operation = .copied
                } else if line.hasPrefix("new file mode ") {
                    operation = .added
                } else if line.hasPrefix("deleted file mode ") {
                    operation = .deleted
                }
            }

            index += 1
        }

        if oldPath == nil {
            operation = .added
        } else if newPath == nil {
            operation = .deleted
        } else if operation == .modified,
            oldPath != newPath
        {
            operation = .renamed
        }

        return PatchChangedFile(
            oldPath: oldPath,
            newPath: newPath,
            operation: operation,
            diffHeader: diffHeader,
            headerLines: headerLines,
            hunks: hunks,
            trailingLines: trailingLines
        )
    }

    private func parseHunk(
        in lines: [String],
        at start: Int
    ) throws -> (
        hunk: PatchHunk,
        nextIndex: Int
    ) {
        let header = lines[start]
        let parsedHeader = try parseHunkHeader(header)
        var oldLine = parsedHeader.oldRange.start
        var newLine = parsedHeader.newRange.start
        var oldCount = 0
        var newCount = 0
        var diffLines: [PatchDiffLine] = []
        var index = start + 1

        func appendInferredContext(
            _ line: String
        ) throws {
            guard oldCount
                < parsedHeader.oldRange.count,
                newCount
                < parsedHeader.newRange.count
            else {
                throw
                    PatchDocumentParserError
                    .invalidHunkLine(line: line)
            }

            diffLines.append(
                PatchDiffLine(
                    kind: .context,
                    content: line,
                    rawText: line,
                    isInferred: true,
                    oldLineNumber: oldLine,
                    newLineNumber: newLine
                )
            )
            oldLine += 1
            newLine += 1
            oldCount += 1
            newCount += 1
        }

        while index < lines.count,
            oldCount < parsedHeader.oldRange.count
                || newCount < parsedHeader.newRange.count
        {
            let line = lines[index]

            if line.hasPrefix("@@ ")
                || line.hasPrefix("diff --git ")
            {
                break
            }

            if line.hasPrefix("\\ No newline at end of file") {
                diffLines.append(
                    PatchDiffLine(
                        kind: .noNewlineMarker,
                        content: String(line.dropFirst()),
                        rawText: line,
                        isInferred: false,
                        oldLineNumber: nil,
                        newLineNumber: nil
                    )
                )
                index += 1
                continue
            }

            guard let marker = line.first else {
                try appendInferredContext(line)
                index += 1
                continue
            }

            let content = String(line.dropFirst())

            switch marker {
            case " ":
                diffLines.append(
                    PatchDiffLine(
                        kind: .context,
                        content: content,
                        rawText: line,
                        isInferred: false,
                        oldLineNumber: oldLine,
                        newLineNumber: newLine
                    )
                )
                oldLine += 1
                newLine += 1
                oldCount += 1
                newCount += 1
            case "+":
                diffLines.append(
                    PatchDiffLine(
                        kind: .addition,
                        content: content,
                        rawText: line,
                        isInferred: false,
                        oldLineNumber: nil,
                        newLineNumber: newLine
                    )
                )
                newLine += 1
                newCount += 1
            case "-":
                diffLines.append(
                    PatchDiffLine(
                        kind: .deletion,
                        content: content,
                        rawText: line,
                        isInferred: false,
                        oldLineNumber: oldLine,
                        newLineNumber: nil
                    )
                )
                oldLine += 1
                oldCount += 1
            default:
                try appendInferredContext(line)
            }

            index += 1
        }

        guard oldCount == parsedHeader.oldRange.count,
            newCount == parsedHeader.newRange.count
        else {
            throw
                PatchDocumentParserError
                .hunkLineCountMismatch(
                    header: header,
                    expectedOld:
                        parsedHeader.oldRange.count,
                    actualOld: oldCount,
                    expectedNew:
                        parsedHeader.newRange.count,
                    actualNew: newCount
                )
        }

        while index < lines.count,
            lines[index].hasPrefix(
                "\\ No newline at end of file"
            )
        {
            let line = lines[index]
            diffLines.append(
                PatchDiffLine(
                    kind: .noNewlineMarker,
                    content: String(line.dropFirst()),
                    rawText: line,
                    isInferred: false,
                    oldLineNumber: nil,
                    newLineNumber: nil
                )
            )
            index += 1
        }

        return (
            PatchHunk(
                oldRange: parsedHeader.oldRange,
                newRange: parsedHeader.newRange,
                sectionHeader: parsedHeader.sectionHeader,
                rawHeader: header,
                lines: diffLines
            ),
            index
        )
    }

    private func parseHunkHeader(
        _ header: String
    ) throws -> (
        oldRange: PatchLineRange,
        newRange: PatchLineRange,
        sectionHeader: String?
    ) {
        guard header.hasPrefix("@@ "),
            let close = header.range(
                of: " @@",
                range: header.index(
                    header.startIndex,
                    offsetBy: 3
                )..<header.endIndex
            )
        else {
            throw
                PatchDocumentParserError
                .malformedHunkHeader(line: header)
        }

        let rangeText = header[
            header.index(
                header.startIndex,
                offsetBy: 3
            )..<close.lowerBound
        ]
        let components = rangeText.split(
            whereSeparator: \.isWhitespace
        )

        guard components.count == 2,
            components[0].hasPrefix("-"),
            components[1].hasPrefix("+"),
            let oldRange = parseRange(
                components[0].dropFirst()
            ),
            let newRange = parseRange(
                components[1].dropFirst()
            )
        else {
            throw
                PatchDocumentParserError
                .malformedHunkHeader(line: header)
        }

        let sectionStart = close.upperBound
        let section = header[sectionStart...]
            .trimmingCharacters(in: .whitespaces)

        return (
            oldRange,
            newRange,
            section.isEmpty ? nil : section
        )
    }

    private func parseRange(
        _ text: Substring
    ) -> PatchLineRange? {
        let components = text.split(
            separator: ",",
            omittingEmptySubsequences: false
        )

        guard
            components.count == 1
                || components.count == 2,
            let start = Int(components[0]),
            start >= 0
        else {
            return nil
        }

        let count: Int

        if components.count == 2 {
            guard let parsedCount = Int(components[1]),
                parsedCount >= 0
            else {
                return nil
            }

            count = parsedCount
        } else {
            count = 1
        }

        return PatchLineRange(
            start: start,
            count: count
        )
    }

    private func path(
        in markerLine: String
    ) -> String? {
        guard markerLine.count >= 4 else {
            return nil
        }

        let value = markerLine.dropFirst(4)
        let path =
            value.split(
                separator: "\t",
                maxSplits: 1,
                omittingEmptySubsequences: false
            ).first.map(String.init) ?? ""

        return normalizedPath(path)
    }

    private func normalizedPath(
        _ path: String
    ) -> String? {
        var result = path

        if result.hasPrefix("\"")
            && result.hasSuffix("\"")
        {
            result.removeFirst()
            result.removeLast()
        }

        guard result != "/dev/null" else {
            return nil
        }

        if result.hasPrefix("a/")
            || result.hasPrefix("b/")
        {
            result.removeFirst(2)
        }

        return result
    }

    private func splitHeaderWords(
        _ line: String
    ) -> [String] {
        var words: [String] = []
        var word = ""
        var quoted = false
        var escaped = false

        for character in line {
            if escaped {
                word.append(character)
                escaped = false
            } else if character == "\\",
                quoted
            {
                escaped = true
            } else if character == "\"" {
                quoted.toggle()
            } else if character.isWhitespace,
                !quoted
            {
                if !word.isEmpty {
                    words.append(word)
                    word = ""
                }
            } else {
                word.append(character)
            }
        }

        if !word.isEmpty {
            words.append(word)
        }

        return words
    }
}
