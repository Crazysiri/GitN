# RFC: Structural diff3 and Monaco conflict editor

- Status: Accepted
- Owner: GitN
- Date: 2026-11-07

## Problem / Evidence
The previous implementation added Kraken-like controls over native drawing/NSTextView and libgit2 zdiff3. It did not reproduce the editing substrate or merge partitioning. Local REA modules 83412 -> 91621 -> 34086 establish a line-array diff3 pipeline with O(NP) edit scripts, ancestor overlap clustering (touching intervals included), and identical-side conflict suppression. Module 90617 establishes ordered source-line membership; 24785 / 19180 establish Monaco and block-relative scroll mapping. Source excerpts are research evidence, not product dependencies.

## Design
Implement the published O(NP) edit-script strategy independently in Swift and build structural hunks with exact ancestor/current/incoming offsets. Read index stages on the GitService actor, compute the pure diff3 in a detached task, then recheck the conflict snapshot before presenting it. Keep the old marker reader only as a compatibility fixture boundary; remove it from production loading. This work changes editor semantics, not Git's merge/index operation.

Use a conflict payload alongside the shared Monaco transport. A separate conflict host creates three persistent Monaco models, native Monaco glyph/whole-line decorations and widgets for conflict selection, and block-relative scroll mapping using cached geometry, animation-frame coalescing and programmatic feedback guards. Each pane renders its own line count compactly; corresponding common/conflict segments map scroll progress at adaptive rates rather than padding shorter panes to the longest or ancestor block. A zero-line side has a compact action header, never fabricated file content. Source-line glyphs appear as checked/unchecked boxes. Side-specific metadata keys avoid rebuilding unchanged zones. Changes update models/decorations without recreating editors. Native document state remains authoritative for save/undo; bridge revisions prevent old edit acknowledgments overwriting newer typing. Session identity rejects stale events. Keyboard and editor-menu undo route through the existing document undo stack so source choices and text share history.

Source-line selection belongs in the document, not the view. It appends selected lines in action order, allows whole-side selection to replace that side's contribution and append it, and tracks per-line membership. Manual edits preserve unrelated source membership and remove edited memberships. GitN retains explicit resolution intent and saved-file/index identity checks.

Missing stage 2 or 3 is a modify/delete conflict, not an empty text side. Route it to explicit keep-modified, keep-deleted, and keep-ancestor choices. GitService validates the conflict snapshot, checks out the selected present index stage through Git (preserving mode and filters) or removes the path, then stages the result with the existing REUC-preserving path. This stays within GitService's existing conflict mutation responsibility.

## Alternatives
Monaco's stock two-pane diff does not supply this three-way model. Keeping native renderers leaves the requested substrate mismatch. Running proprietary Kraken modules is excluded; reference modules are used only for local differential evidence.

## Validation / Risks
See intake. Primary risks are repeated-line tie breaks, zero-length intervals, EOF and CRLF, asynchronous edit echoes, manual-edit source membership, and undo across selections. Automated tests cover those boundaries; real WebKit smoke covers Monaco geometry/runtime rather than mocked APIs alone. No unrelated RepoViewModel/GitService responsibilities are added.
