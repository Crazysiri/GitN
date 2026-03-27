import AppKit

// MARK: - NSTextView subclass with built-in line-number gutter
//
// Line numbers are drawn directly inside drawBackground(in:), which runs in
// the text view's own coordinate system. The gutter therefore scrolls together
// with the text with zero extra view-hierarchy complexity, and alignment is
// derived straight from NSLayoutManager.lineFragmentRect — always pixel-perfect.
//
// Used by MarkdownEditorView.

class LineNumberTextView: NSTextView {

    // Gutter geometry
    static  let gutterWidth : CGFloat = 48
    private let vPad        : CGFloat = 16  // vertical inset (top & bottom)
    private let hTextPad    : CGFloat = 16  // padding between gutter right-edge and text

    // Gutter styling
    var lineFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    var lineColor = NSColor(white: 0.38, alpha: 1)
    var gutterBackgroundColor = NSColor(red: 0.094, green: 0.098, blue: 0.110, alpha: 1)
    var gutterSeparatorColor = NSColor.white.withAlphaComponent(0.06)
    private var cachedLineStarts: [Int] = [0]
    private var cachedStringLength = -1
    var drawsInlineGutter = true

    // MARK: Init
    //
    // NSTextView has two designated initializers:
    //   init(frame:)                  → creates a brand-new, complete text system
    //   init(frame:textContainer:)    → attaches to an existing text system
    //
    // We must override BOTH so Swift allows us to call init(frame:) on this
    // subclass.  Passing nil for textContainer gives a textView with NO text
    // system at all, which is why we never use that path.

    override init(frame: NSRect) {
        super.init(frame: frame)   // NSTextView builds NSTextStorage/LayoutManager/Container
        configure()
    }

    override init(frame: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        // textContainerInset is symmetric (width = left = right).
        // We push text right far enough to clear the gutter; the matching right
        // margin is acceptable for a code viewer.
        textContainerInset = NSSize(width: Self.gutterWidth + hTextPad, height: vPad)
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateLineStartCache()
    }

    // MARK: Frame / layout

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // super.setFrameSize triggers widthTracksTextView to update the text
        // container width, but NSTextView only marks specific (lazily-known) glyph
        // rects dirty via textContainerChangedGeometry.  When no layout has been
        // computed yet the dirty-rect set is empty, so drawBackground is never
        // called for the full new bounds and the view stays blank.
        // Setting needsDisplay here guarantees the whole new frame is redrawn.
        needsDisplay = true
    }

    // MARK: Drawing

    override func drawBackground(in rect: NSRect) {
        // Force synchronous layout before glyph drawing.
        // The text view may start with a zero-width frame (SwiftUI assigns the
        // real frame asynchronously); ensureLayout here makes certain glyphs are
        // positioned for the current container width before NSTextView draws them.
        if let lm = layoutManager, let tc = textContainer { lm.ensureLayout(for: tc) }
        super.drawBackground(in: rect)          // fills rect with backgroundColor

        guard drawsInlineGutter else { return }

        let gutterMinX = pinnedViewportMinX(for: rect)

        // Gutter background (overdraws the left slice)
        gutterBackgroundColor.setFill()
        NSRect(x: gutterMinX, y: rect.minY,
               width: Self.gutterWidth, height: rect.height).fill()

        gutterSeparatorColor.setFill()
        NSRect(x: gutterMinX + Self.gutterWidth - 1, y: rect.minY,
               width: 1, height: rect.height).fill()

        drawLineNumbers(in: rect, gutterMinX: gutterMinX)
    }

    func pinnedViewportMinX(for dirtyRect: NSRect) -> CGFloat {
        enclosingScrollView?.contentView.bounds.minX ?? dirtyRect.minX
    }

    private func drawLineNumbers(in dirtyRect: NSRect, gutterMinX: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: lineFont,
            .foregroundColor: lineColor
        ]
        enumerateVisibleLogicalLines(in: dirtyRect) { lineNum, _, frag in
            let label = "\(lineNum)" as NSString
            let sz = label.size(withAttributes: attrs)
            label.draw(
                at: NSPoint(
                    x: gutterMinX + Self.gutterWidth - sz.width - 8,
                    y: frag.minY + vPad + (frag.height - sz.height) / 2
                ),
                withAttributes: attrs
            )
        }
    }

    func enumerateVisibleLogicalLines(
        in dirtyRect: NSRect,
        using body: (_ lineNumber: Int, _ charLocation: Int, _ fragmentRect: NSRect) -> Void
    ) {
        guard let lm = layoutManager,
              let tc = textContainer,
              lm.numberOfGlyphs > 0
        else { return }

        let nsStr = string as NSString
        refreshLineStartCacheIfNeeded(length: nsStr.length, string: nsStr)

        let containerDirtyRect = dirtyRect.offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y)
        let visibleGlyphRange = lm.glyphRange(forBoundingRect: containerDirtyRect, in: tc)
        let visibleCharRange = lm.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)
        let startChar = max(0, visibleCharRange.location)
        let endChar = min(nsStr.length, NSMaxRange(visibleCharRange) + 1)

        var lineIndex = lineIndexForCharacterLocation(startChar)
        while lineIndex < cachedLineStarts.count {
            let charIdx = cachedLineStarts[lineIndex]
            if charIdx >= endChar { break }

            let glyphIdx = lm.glyphIndexForCharacter(at: charIdx)
            var effectiveRange = NSRange()
            let frag = lm.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: &effectiveRange)
            let lineY = frag.minY + vPad
            if lineY > dirtyRect.maxY { break }

            if lineY + frag.height >= dirtyRect.minY {
                body(lineIndex + 1, charIdx, frag)
            }
            lineIndex += 1
        }
    }

    private func invalidateLineStartCache() {
        cachedStringLength = -1
        cachedLineStarts = [0]
    }

    private func refreshLineStartCacheIfNeeded(length: Int, string: NSString) {
        guard cachedStringLength != length else { return }

        cachedStringLength = length
        cachedLineStarts = [0]
        guard length > 0 else { return }

        var index = 0
        while index < length {
            let lineRange = string.lineRange(for: NSRange(location: index, length: 0))
            let next = NSMaxRange(lineRange)
            if next < length {
                cachedLineStarts.append(next)
            }
            guard next > index else { break }
            index = next
        }
    }

    private func lineIndexForCharacterLocation(_ location: Int) -> Int {
        var low = 0
        var high = max(cachedLineStarts.count - 1, 0)

        while low < high {
            let mid = (low + high + 1) / 2
            if cachedLineStarts[mid] <= location {
                low = mid
            } else {
                high = mid - 1
            }
        }

        return low
    }
}
