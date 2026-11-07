import Foundation

struct MonacoConflictPayload: Encodable, Equatable {
    struct Block: Encodable, Equatable {
        let id: Int
        let ours: [Int]
        let theirs: [Int]
        let output: [Int]
        let ancestorLength: Int
        let selectedOurs: [Int]
        let selectedTheirs: [Int]
        let allOurs: Bool
        let allTheirs: Bool
        let resolved: Bool
    }
    let path: String
    let language: String
    let oursLabel: String
    let theirsLabel: String
    let oursText: String
    let theirsText: String
    let outputText: String
    let blocks: [Block]
    let origins: [String]
    let externalRevision: Int
    let navigationID: Int
    let currentBlock: Int
    var acknowledgedEdit: Int = 0

    @MainActor init(path: String, sides: ConflictSides, document: ConflictEditorDocument,
         externalRevision: Int, navigationID: Int, currentBlock: Int) {
        self.path = path
        language = RepoViewModel.monacoLanguage(for: path.sourceLanguage)
        oursLabel = sides.oursLabel; theirsLabel = sides.theirsLabel
        oursText = sides.oursLines.joined(separator: "\n")
        theirsText = sides.theirsLines.joined(separator: "\n")
        outputText = document.outputText
        blocks = zip(sides.markers, document.blocks).map { marker, block in
            let range = block.activeRange ?? (block.anchor.preferredLine..<block.anchor.preferredLine)
            return Block(id: block.id,
                ours: [marker.oursRange.lowerBound, marker.oursRange.upperBound],
                theirs: [marker.theirsRange.lowerBound, marker.theirsRange.upperBound],
                output: [range.lowerBound, range.upperBound],
                ancestorLength: marker.baseLines.count,
                selectedOurs: document.selectedLineIndices(blockID: block.id, side: .current),
                selectedTheirs: document.selectedLineIndices(blockID: block.id, side: .incoming),
                allOurs: block.selectedSources.current, allTheirs: block.selectedSources.incoming,
                resolved: block.isResolved)
        }
        origins = document.outputLineOrigins.map {
            switch $0 {
            case .common: return "common"
            case .ancestor: return "ancestor"
            case .current: return "ours"
            case .incoming: return "theirs"
            case .manual: return "manual"
            }
        }
        self.externalRevision = externalRevision
        self.navigationID = navigationID
        self.currentBlock = currentBlock
    }
}
