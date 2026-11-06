const JsDiff = require("diff");

  function splitLines(text) {
    if (!text) {
      return [];
    }
    const lines = text.split("\n");
    if (lines.length > 0 && lines[lines.length - 1] === "") {
      lines.pop();
    }
    return lines;
  }

  /**
   * Find the changed character sub-range within `source` compared to `other`.
   * Trims the common prefix and suffix, then returns 1-based column positions
   * (UTF-16, matching Monaco column semantics) of the differing middle region.
   * Returns null when source === other or when the changed region is empty.
   *
   * Algorithm mirrors Swift's changedUTF16Range(in:comparedTo:) in RepoViewModel.
   */
  function findChangedCharRange(source, other) {
    if (source === other) {
      return null;
    }
    const sourceChars = Array.from(source);
    const otherChars = Array.from(other);

    let prefixLen = 0;
    while (
      prefixLen < sourceChars.length &&
      prefixLen < otherChars.length &&
      sourceChars[prefixLen] === otherChars[prefixLen]
    ) {
      prefixLen += 1;
    }

    let sourceSuffix = sourceChars.length;
    let otherSuffix = otherChars.length;
    while (
      sourceSuffix > prefixLen &&
      otherSuffix > prefixLen &&
      sourceChars[sourceSuffix - 1] === otherChars[otherSuffix - 1]
    ) {
      sourceSuffix -= 1;
      otherSuffix -= 1;
    }

    // Convert Unicode code-point indices to UTF-16 string lengths (JS native).
    const startColumn = sourceChars.slice(0, prefixLen).join("").length + 1;
    const endColumn = sourceChars.slice(0, sourceSuffix).join("").length + 1;

    if (endColumn <= startColumn) {
      return null;
    }
    return { startColumn, endColumn };
  }

  function buildUnifiedDiffModel(originalText, modifiedText) {
    if (!JsDiff || typeof JsDiff.diffLines !== "function") {
      throw new Error("JsDiff runtime is not available");
    }

    const parts = JsDiff.diffLines(originalText, modifiedText, {
      newlineIsToken: false,
      ignoreWhitespace: false,
      timeout: 1200,
      maxEditLength: 20000,
    });
    if (!parts) { throw new Error("Diff computation exceeded its budget. Text remains available."); }
    const rows = [];
    const lineNumberMap = new Map();
    const additionDecorations = [];
    const deletionEntries = [];
    // Maps new line number -> { startColumn, endColumn } for paired additions.
    const additionInlineHighlights = new Map();
    let oldLine = 1;
    let newLine = 1;

    for (let index = 0; index < parts.length; index += 1) {
      const part = parts[index];
      const lines = splitLines(part.value);
      const lineCount = lines.length;

      if (part.removed) {
        const nextPart = parts[index + 1];
        const removedLines = lines;
        const addedLines = nextPart && nextPart.added ? splitLines(nextPart.value) : [];
        const anchorModifiedLineNumber = newLine;

        const deletedLines = removedLines.map((content, offset) => ({
          kind: "deletion",
          oldLineNum: oldLine + offset,
          newLineNum: null,
          content,
          inlineHighlight: null,
        }));
        for (const row of deletedLines) {
          rows.push(row);
        }

        // Pair each deleted line with the corresponding added line (same algorithm as
        // Swift's buildInlineHighlights / changedUTF16Range in RepoViewModel).
        const pairCount = Math.min(removedLines.length, addedLines.length);
        for (let pairIndex = 0; pairIndex < pairCount; pairIndex += 1) {
          const delHighlight = findChangedCharRange(removedLines[pairIndex], addedLines[pairIndex]);
          const addHighlight = findChangedCharRange(addedLines[pairIndex], removedLines[pairIndex]);
          if (delHighlight) {
            deletedLines[pairIndex].inlineHighlight = delHighlight;
          }
          if (addHighlight) {
            additionInlineHighlights.set(newLine + pairIndex, addHighlight);
          }
        }

        const modifiedStartLineNumber = addedLines.length > 0 ? newLine : 0;
        const modifiedEndLineNumber = addedLines.length > 0 ? newLine + addedLines.length - 1 : 0;
        deletionEntries.push({
          anchorLine: Math.max(anchorModifiedLineNumber, 1),
          modifiedStartLineNumber,
          modifiedEndLineNumber,
          anchorModifiedLineNumber,
          deletedLines,
          hasAddition: addedLines.length > 0,
        });

        for (let offset = 0; offset < addedLines.length; offset += 1) {
          const lineNumber = newLine + offset;
          const row = {
            kind: "addition",
            oldLineNum: null,
            newLineNum: lineNumber,
            content: addedLines[offset],
          };
          rows.push(row);
          lineNumberMap.set(lineNumber, {
            oldLineNum: null,
            newLineNum: lineNumber,
          });
        }
        if (addedLines.length > 0) {
          additionDecorations.push({
            startLineNumber: newLine,
            endLineNumber: newLine + addedLines.length - 1,
          });
        }

        oldLine += removedLines.length;
        if (nextPart && nextPart.added) {
          newLine += addedLines.length;
          index += 1;
        }
        continue;
      }

      if (part.added) {
        for (let offset = 0; offset < lineCount; offset += 1) {
          const lineNumber = newLine + offset;
          const row = {
            kind: "addition",
            oldLineNum: null,
            newLineNum: lineNumber,
            content: lines[offset],
          };
          rows.push(row);
          lineNumberMap.set(lineNumber, {
            oldLineNum: null,
            newLineNum: lineNumber,
          });
        }
        additionDecorations.push({
          startLineNumber: newLine,
          endLineNumber: newLine + lineCount - 1,
        });
        newLine += lineCount;
        continue;
      }

      for (let offset = 0; offset < lineCount; offset += 1) {
        const oldLineNum = oldLine + offset;
        const newLineNum = newLine + offset;
        const row = {
          kind: "context",
          oldLineNum,
          newLineNum,
          content: lines[offset],
        };
        rows.push(row);
        lineNumberMap.set(newLineNum, {
          oldLineNum,
          newLineNum,
        });
      }
      oldLine += lineCount;
      newLine += lineCount;
    }

    return {
      rows,
      lineNumberMap,
      additionDecorations,
      deletionEntries,
      additionInlineHighlights,
    };
  }


module.exports = { buildUnifiedDiffModel };
