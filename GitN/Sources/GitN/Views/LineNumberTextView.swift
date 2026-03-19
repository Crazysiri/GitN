import AppKit

// MARK: - NSTextView subclass with built-in line-number gutter
//
// Line numbers are drawn directly inside drawBackground(in:), which runs in
// the text view's own coordinate system. The gutter therefore scrolls together
// with the text with zero extra view-hierarchy complexity, and alignment is
// derived straight from NSLayoutManager.lineFragmentRect — always pixel-perfect.
//
// Used by both SourcePreviewView (read-only) and MarkdownEditorView (editable).

final class LineNumberTextView: NSTextView {

    // Gutter geometry
    static  let gutterWidth : CGFloat = 48
    private let vPad        : CGFloat = 16  // vertical inset (top & bottom)
    private let hTextPad    : CGFloat = 16  // padding between gutter right-edge and text

    // Gutter styling
    private let lineFont   = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private let lineColor  = NSColor(white: 0.38, alpha: 1)
    private let gutterBg   = NSColor(red: 0.094, green: 0.098, blue: 0.110, alpha: 1)
    private let dividerClr = NSColor(white: 0.20, alpha: 1)

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

        // Gutter background (overdraws the left slice)
        gutterBg.setFill()
        NSRect(x: 0, y: rect.minY,
               width: Self.gutterWidth, height: rect.height).fill()

        // Separator line
        dividerClr.setFill()
        NSRect(x: Self.gutterWidth - 1, y: rect.minY,
               width: 1, height: rect.height).fill()

        drawLineNumbers(in: rect)
    }

    private func drawLineNumbers(in dirtyRect: NSRect) {
        guard let lm = layoutManager, lm.numberOfGlyphs > 0 else { return }

        let nsStr     = string as NSString
        let totalLen  = nsStr.length
        let numGlyphs = lm.numberOfGlyphs
        let insetY    = vPad                  // matches textContainerInset.height

        let attrs: [NSAttributedString.Key: Any] = [
            .font: lineFont,
            .foregroundColor: lineColor
        ]

        var lineNum = 1
        var charIdx = 0

        while charIdx < totalLen {
            let glyphIdx = lm.glyphIndexForCharacter(at: charIdx)
            guard glyphIdx < numGlyphs else { break }

            var effRange = NSRange()
            let frag     = lm.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: &effRange)
            let lineY    = frag.minY + insetY          // text-view coordinate

            // Early exit once past the dirty rect
            if lineY > dirtyRect.maxY { break }

            // Draw only what falls inside the dirty rect
            if lineY + frag.height >= dirtyRect.minY {
                let label = "\(lineNum)" as NSString
                let sz    = label.size(withAttributes: attrs)
                label.draw(
                    at: NSPoint(
                        x: Self.gutterWidth - sz.width - 8,
                        y: lineY + (frag.height - sz.height) / 2
                    ),
                    withAttributes: attrs
                )
            }

            // Advance to the next *logical* line (skips wrapped fragments)
            let lineRange = nsStr.lineRange(for: NSRange(location: charIdx, length: 0))
            let next      = NSMaxRange(lineRange)
            guard next > charIdx else { break }
            charIdx = next
            lineNum += 1
        }
    }
}
