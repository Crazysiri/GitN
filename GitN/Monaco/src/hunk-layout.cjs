// Display-only ranges. Monaco changes describe text differences; Git control
// indices remain authoritative for patch operations.
function buildHunkLayout(changes, originalLineCount, modifiedLineCount, context = 3) {
  const counts = { original: Math.max(1, originalLineCount), modified: Math.max(1, modifiedLineCount) };
  const hunks = [];
  for (const change of changes || []) {
    const sides = {};
    for (const side of ['original', 'modified']) {
      const start = change[`${side}StartLineNumber`];
      const end = change[`${side}EndLineNumber`];
      // End == 0 means an empty interval after start (insertion/deletion).
      const changed = end === 0 ? null : { start, end };
      sides[side] = {
        start: Math.max(1, start - context + (end === 0 ? 1 : 0)),
        end: Math.min(counts[side], (end === 0 ? start : end) + context),
        changes: changed ? [changed] : [],
      };
      sides[side].start = Math.min(sides[side].start, counts[side]);
      sides[side].end = Math.max(sides[side].start, sides[side].end);
    }
    const previous = hunks.at(-1);
    if (previous && (sides.original.start <= previous.original.end + 1 ||
                     sides.modified.start <= previous.modified.end + 1)) {
      for (const side of ['original', 'modified']) {
        previous[side].end = Math.max(previous[side].end, sides[side].end);
        previous[side].changes.push(...sides[side].changes);
      }
    } else {
      hunks.push(sides);
    }
  }
  const hidden = {};
  for (const side of ['original', 'modified']) {
    hidden[side] = [];
    let next = 1;
    for (const hunk of hunks) {
      if (next < hunk[side].start) hidden[side].push({ start: next, end: hunk[side].start - 1 });
      next = hunk[side].end + 1;
    }
    if (next <= counts[side]) hidden[side].push({ start: next, end: counts[side] });
  }
  return { hunks, hidden };
}

function controlsForHunk(hunk, controls) {
  const seen = new Set();
  return (controls || []).filter(control => {
    if (seen.has(control.hunkIndex)) return false;
    const matches = ['original', 'modified'].some(side => {
      const prefix = side === 'original' ? 'old' : 'new';
      const start = control[`${prefix}StartLine`] ?? control[`${prefix}LineNumber`];
      const end = control[`${prefix}EndLine`] ?? start;
      return Number.isInteger(start) && hunk[side].changes.some(range => start <= range.end && end >= range.start);
    });
    if (matches) seen.add(control.hunkIndex);
    return matches;
  });
}

function hunkHeader(hunk) {
  const range = side => `${side.start},${side.end - side.start + 1}`;
  return `@@ -${range(hunk.original)} +${range(hunk.modified)} @@`;
}

module.exports = { buildHunkLayout, controlsForHunk, hunkHeader };
