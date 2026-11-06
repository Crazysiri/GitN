# RFC: Per-Block Conflict Resolution Gate

- Status: Implementing
- Owner: GitN
- Date: 2026-11-06

## Design

The document starts every conflict block as unresolved even though its output initially contains ancestor lines. Selecting a side resolves that block. Manually editing or deleting lines within a block marks explicit resolution. A Keep Base action marks the unchanged ancestor output as an explicit user decision. Reset returns all blocks to unresolved. Deselecting the last side returns the block to unresolved unless a later manual edit resolved it.

The save command examines every block. If any remains unresolved it displays a warning and does not write or stage the output. The UI shows a count and offers a direct Keep Base action for the currently selected block. Undo works because the document remains a value snapshot in the existing undo manager.

## Boundaries and risks

- The model owns intent; the view never infers resolution from text equality.
- This is a safety gate, not a draft-save feature. Future work may split Save Draft from Mark Resolved.
- Very unusual edits spanning multiple blocks should resolve only the blocks whose mapped output ranges changed; tests cover representative edits and deletion.
