const test = require('node:test');
const assert = require('node:assert/strict');
const { mapOffset, segments, compactGeometry } = require('../../Sources/GitN/Resources/Monaco/conflict-host.js');

test('maps common and conflict segments locally rather than whole-file percentages', () => {
  const source = [[0, 100], [100, 500], [500, 600]];
  const target = [[0, 200], [200, 300], [300, 350]];
  assert.equal(mapOffset(300, source, target), 250);
  assert.equal(mapOffset(550, source, target), 325);
  assert.equal(mapOffset(250, target, source), 300);
  assert.equal(mapOffset(-20, source, target), 0);
  assert.equal(mapOffset(999, source, target), 350);
});
test('keeps empty conflict intervals and empty common segments in correspondence', () => {
  const blocks = [{ ours: [0, 0], theirs: [0, 2] }, { ours: [2, 4], theirs: [4, 4] }];
  assert.deepEqual(segments(blocks, 'ours', 5), [[0, 0], [0, 0], [0, 2], [2, 4], [4, 5]]);
  assert.deepEqual(segments(blocks, 'theirs', 5), [[0, 0], [0, 2], [2, 4], [4, 4], [4, 5]]);
  assert.equal(mapOffset(0, [[0, 0], [0, 100]], [[0, 0], [0, 300]]), 0);
  assert.equal(mapOffset(50, [[0, 0], [0, 100]], [[0, 0], [0, 300]]), 150);
});

test('each pane stays compact and changes scroll speed inside unequal conflict blocks', () => {
  const blocks = [
    {ours: [10, 11], theirs: [10, 20], output: [10, 15]},
    {ours: [31, 33], theirs: [40, 42], output: [35, 37]},
  ];
  const ours = compactGeometry(blocks, 'ours', 50);
  const theirs = compactGeometry(blocks, 'theirs', 59);
  const output = compactGeometry(blocks, 'output', 54);
  assert.deepEqual(ours[1], [190, 234]);
  assert.deepEqual(theirs[1], [190, 405]);
  assert.equal(ours.at(-1)[1], 50 * 19 + 2 * 25);
  assert.equal(theirs.at(-1)[1], 59 * 19 + 2 * 25);
  assert.equal(output.at(-1)[1], 54 * 19 + 2 * 25);
  assert.equal(mapOffset(212, ours, theirs), 297.5);
  assert.equal(mapOffset(234, ours, theirs), 405);

  const expanded = [
    {...blocks[0], output: [10, 25]},
    {...blocks[1], output: [45, 47]},
  ];
  const grownOutput = compactGeometry(expanded, 'output', 64);
  assert.deepEqual(compactGeometry(blocks, 'ours', 50), ours);
  assert.equal(grownOutput.at(-1)[1] - output.at(-1)[1], 10 * 19);
  assert.equal(mapOffset(ours[2][0], ours, grownOutput), grownOutput[2][0]);
});

test('an empty source block costs only its compact action header', () => {
  const blocks = [{ours: [5, 5], theirs: [5, 15], output: [5, 5]}];
  const ours = compactGeometry(blocks, 'ours', 20);
  const theirs = compactGeometry(blocks, 'theirs', 30);
  assert.deepEqual(ours[1], [95, 120]);
  assert.deepEqual(theirs[1], [95, 310]);
  assert.equal(ours.at(-1)[1], 20 * 19 + 25);
  assert.equal(mapOffset(107.5, ours, theirs), 202.5);
});
