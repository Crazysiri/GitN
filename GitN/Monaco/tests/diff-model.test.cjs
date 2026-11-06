const test = require('node:test');
const assert = require('node:assert/strict');
const { buildUnifiedDiffModel } = require('../src/diff-model.cjs');

test('maps insertion, deletion and unchanged lines', () => {
  const result = buildUnifiedDiffModel('one\ntwo\nthree\n', 'one\nnew\nthree\n');
  assert.deepEqual(result.rows.map((row) => row.kind), ['context', 'deletion', 'addition', 'context']);
  assert.equal(result.deletionEntries[0].deletedLines[0].content, 'two');
  assert.equal(result.additionDecorations[0].startLineNumber, 2);
  assert.deepEqual(result.lineNumberMap.get(3), { oldLineNum: 3, newLineNum: 3 });
});

test('maps a pure deletion at the end of a file', () => {
  const result = buildUnifiedDiffModel('first\nlast\n', 'first\n');
  assert.equal(result.deletionEntries.length, 1);
  assert.equal(result.deletionEntries[0].deletedLines[0].content, 'last');
  assert.equal(result.additionDecorations.length, 0);
});

test('uses UTF-16 Monaco columns for changed Unicode text', () => {
  const result = buildUnifiedDiffModel('😀old!\n', '😀new!\n');
  assert.deepEqual(result.additionInlineHighlights.get(1), { startColumn: 3, endColumn: 6 });
});

test('handles ten thousand unchanged lines with a final edit', () => {
  const before = Array.from({ length: 10000 }, (_, i) => 'line ' + i).join('\n') + '\n';
  const after = before + 'tail\n';
  const result = buildUnifiedDiffModel(before, after);
  assert.equal(result.rows.length, 10001);
  assert.equal(result.additionDecorations.at(-1).startLineNumber, 10001);
});

test('rejects a diff beyond its edit budget without hiding text', () => {
  const before = 'before\n'.repeat(25000);
  const after = 'after\n'.repeat(25000);
  assert.throws(() => buildUnifiedDiffModel(before, after), /budget/);
});
