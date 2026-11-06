import Foundation

/// Ordered terminal tabs and deterministic selection, independent of PTY/UI lifetime.
struct TerminalSessionSelection {
    private(set) var orderedIDs: [UUID] = []
    private(set) var activeID: UUID?

    mutating func append(_ id: UUID) {
        guard !orderedIDs.contains(id) else { return }
        orderedIDs.append(id)
        activeID = id
    }

    mutating func select(_ id: UUID) {
        guard orderedIDs.contains(id) else { return }
        activeID = id
    }

    mutating func close(_ id: UUID) {
        guard let index = orderedIDs.firstIndex(of: id) else { return }
        orderedIDs.remove(at: index)
        if activeID == id {
            activeID = orderedIDs.indices.contains(index)
                ? orderedIDs[index]
                : orderedIDs.last
        }
    }

    mutating func closeOthers(keeping id: UUID) -> [UUID] {
        guard orderedIDs.contains(id) else { return [] }
        let removed = orderedIDs.filter { $0 != id }
        orderedIDs = [id]
        activeID = id
        return removed
    }

    mutating func move(_ id: UUID, by offset: Int) {
        guard let index = orderedIDs.firstIndex(of: id) else { return }
        let destination = index + offset
        guard orderedIDs.indices.contains(destination) else { return }
        orderedIDs.remove(at: index)
        orderedIDs.insert(id, at: destination)
    }

    mutating func selectAdjacent(_ offset: Int) {
        guard !orderedIDs.isEmpty else { return }
        let current = activeID.flatMap(orderedIDs.firstIndex) ?? 0
        let next = (current + offset % orderedIDs.count + orderedIDs.count) % orderedIDs.count
        activeID = orderedIDs[next]
    }
}
