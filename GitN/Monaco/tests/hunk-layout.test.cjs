const test = require('node:test');
const assert = require('node:assert/strict');
const { buildHunkLayout, controlsForHunk, hunkHeader } = require('../src/hunk-layout.cjs');
const change = (oldStart, oldEnd, newStart = oldStart, newEnd = oldEnd) => ({
  originalStartLineNumber: oldStart, originalEndLineNumber: oldEnd,
  modifiedStartLineNumber: newStart, modifiedEndLineNumber: newEnd,
});

test('isolated hunks crop the document complement and retain source line ranges', () => {
  const layout = buildHunkLayout([change(10, 11), change(40, 40)], 80, 80);
  assert.equal(layout.hunks.length, 2);
  assert.equal(hunkHeader(layout.hunks[0]), '@@ -7,8 +7,8 @@');
  assert.deepEqual(layout.hidden.modified, [{start: 1, end: 6}, {start: 15, end: 36}, {start: 44, end: 80}]);
});

test('nearby changes merge context but preserve changed intervals for action matching', () => {
  const layout = buildHunkLayout([change(10, 10), change(17, 17), change(40, 40)], 50, 50);
  assert.equal(layout.hunks.length, 2);
  const controls = [{hunkIndex: 5, newStartLine: 10, newEndLine: 10},
    {hunkIndex: 9, newStartLine: 17, newEndLine: 17},
    {hunkIndex: 9, newStartLine: 17}, {hunkIndex: 12, newStartLine: 40}];
  assert.deepEqual(controlsForHunk(layout.hunks[0], controls).map(c => c.hunkIndex), [5,9]);
  assert.deepEqual(controlsForHunk(layout.hunks[1], controls).map(c => c.hunkIndex), [12]);
});

test('actions do not attach to a neighboring block merely because its context overlaps a control', () => {
  const layout = buildHunkLayout([change(10, 10)], 30, 30);
  assert.deepEqual(controlsForHunk(layout.hunks[0], [{hunkIndex: 2, newStartLine: 13}]), []);
});

test('pure insertions and deletions use the actual changed side, including file boundaries', () => {
  const added = buildHunkLayout([change(0, 0, 1, 5)], 1, 5);
  assert.equal(added.hunks[0].original.start, 1);
  assert.equal(added.hunks[0].modified.end, 5);
  assert.deepEqual(controlsForHunk(added.hunks[0], [{hunkIndex: 7, newStartLine: 1}]).map(c => c.hunkIndex), [7]);
  const deleted = buildHunkLayout([change(1, 5, 0, 0)], 5, 1);
  assert.deepEqual(controlsForHunk(deleted.hunks[0], [{hunkIndex: 4, oldStartLine: 1}]).map(c => c.hunkIndex), [4]);
  const eof = buildHunkLayout([change(50, 50, 49, 0)], 50, 49);
  assert.equal(eof.hunks[0].modified.end, 49);
  assert.ok(eof.hunks.every(h => h.original.start <= h.original.end && h.modified.start <= h.modified.end));
});

test('unchanged and empty files contain no hunk sections', () => {
  assert.equal(buildHunkLayout([], 1, 1).hunks.length, 0);
  assert.equal(buildHunkLayout(null, 30, 30).hunks.length, 0);
});
