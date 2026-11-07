import Foundation

/// Line-array diff3: O(NP) edit scripts against the ancestor, then union touching
/// ancestor intervals. Coordinates come from the scripts, never marker text.
enum StructuralDiff3 {
    struct Edit: Equatable {
        let base: Range<Int>
        let side: Range<Int>
    }

    static func edits(from original: [String], to modified: [String], maxP: Int? = nil) -> [Edit] {
        let swapped = original.count >= modified.count
        let a = swapped ? modified : original
        let b = swapped ? original : modified
        let n = a.count, m = b.count, delta = m - n
        struct Snake { let x: Int; let y: Int; let endX: Int; let endY: Int; let previous: Int }
        var furthest: [Int: Int] = [:], paths: [Int: Int] = [:], snakes: [Snake] = []
        func advance(_ k: Int) {
            let down = (furthest[k - 1] ?? -1) + 1
            let across = furthest[k + 1] ?? -1
            let previous = paths[down > across ? k - 1 : k + 1] ?? -1
            var y = max(down, across), x = y - k
            let startX = x, startY = y
            while x < n && y < m && x >= 0 && y >= 0 && a[x] == b[y] { x += 1; y += 1 }
            furthest[k] = y
            if x != startX {
                paths[k] = snakes.count
                snakes.append(Snake(x: startX, y: startY, endX: x, endY: y, previous: previous))
            } else { paths[k] = previous }
        }
        var p = -1
        repeat {
            p += 1
            // The merge calculation is unbounded for reference parity. Interactive
            // output edits may set a budget and use one replacement for a huge paste.
            if let maxP, p > maxP {
                return [Edit(base: 0..<original.count, side: 0..<modified.count)]
            }
            if -p < delta { for k in (-p)..<delta { advance(k) } }
            if delta + p > delta { for k in stride(from: delta + p, through: delta + 1, by: -1) { advance(k) } }
            advance(delta)
        } while furthest[delta] != m
        var cursorX = n, cursorY = m, path = paths[delta] ?? -1
        var result: [Edit] = []
        func appendGap(_ x: Int, _ y: Int) {
            guard x != cursorX || y != cursorY else { return }
            result.append(Edit(base: swapped ? y..<cursorY : x..<cursorX,
                               side: swapped ? x..<cursorX : y..<cursorY))
        }
        while path >= 0 {
            let snake = snakes[path]
            appendGap(snake.endX, snake.endY)
            cursorX = snake.x; cursorY = snake.y; path = snake.previous
        }
        appendGap(0, 0)
        return result.reversed()
    }

    static func makeSides(base: [String], ours: [String], theirs: [String],
                          oursLabel: String, theirsLabel: String) -> ConflictSides {
        struct Change { let edit: Edit; let current: Bool; let order: Int }
        let left = edits(from: base, to: ours), right = edits(from: base, to: theirs)
        var changes: [Change] = []
        changes += left.enumerated().map { Change(edit: $0.element, current: true, order: $0.offset) }
        changes += right.enumerated().map { Change(edit: $0.element, current: false, order: left.count + $0.offset) }
        changes.sort {
            if $0.edit.base.lowerBound == $1.edit.base.lowerBound { return $0.order < $1.order }
            return $0.edit.base.lowerBound < $1.edit.base.lowerBound
        }
        var output: [String] = [], regions: [ConflictRegion] = []
        var baseCursor = 0, leftCursor = 0, rightCursor = 0, index = 0
        while index < changes.count {
            let first = index, start = changes[index].edit.base.lowerBound
            var end = changes[index].edit.base.upperBound
            while index + 1 < changes.count && changes[index + 1].edit.base.lowerBound <= end {
                index += 1; end = max(end, changes[index].edit.base.upperBound)
            }
            let common = start - baseCursor
            output += base[baseCursor..<start]
            leftCursor += common; rightCursor += common
            let group = changes[first...index]
            func sideRange(current: Bool, cursor: Int) -> Range<Int> {
                let edits: [Edit] = group.filter { $0.current == current }.map { $0.edit }
                guard let first = edits.first, let last = edits.last else { return cursor..<(cursor + end - start) }
                return (first.side.lowerBound + start - first.base.lowerBound)..<(last.side.upperBound + end - last.base.upperBound)
            }
            let a = sideRange(current: true, cursor: leftCursor)
            let b = sideRange(current: false, cursor: rightCursor)
            let hasLeft = group.contains { $0.current }, hasRight = group.contains { !$0.current }
            if hasLeft && hasRight && !ours[a].elementsEqual(theirs[b]) {
                let outputStart = output.count
                output += base[start..<end]
                regions.append(ConflictRegion(id: regions.count, oursRange: a, theirsRange: b,
                    baseRange: start..<end, outputRange: outputStart..<output.count,
                    currentLines: Array(ours[a]), baseLines: Array(base[start..<end]),
                    incomingLines: Array(theirs[b]), rawConflictLines: []))
            } else {
                output += hasLeft ? Array(ours[a]) : Array(theirs[b])
            }
            baseCursor = end; leftCursor = a.upperBound; rightCursor = b.upperBound
            index += 1
        }
        output += base[baseCursor...]
        return ConflictSides(oursLabel: oursLabel, theirsLabel: theirsLabel, baseLines: base,
            outputLines: output, oursLines: ours, theirsLines: theirs,
            mergedText: output.joined(separator: "\n"), markers: regions, usesStructuralModel: true)
    }
}
