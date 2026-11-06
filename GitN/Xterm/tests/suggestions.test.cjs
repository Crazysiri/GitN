'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { TabMode, readInput, handleKey, moveSelection } = require('../src/suggestions.cjs');

function makeBuffer(lines, baseY, cursorY, cursorX) {
  return {
    baseY,
    cursorY,
    cursorX,
    getLine(absY) {
      const text = lines[absY];
      return text === undefined ? null : { text, length: text.length };
    },
  };
}

test('readInput returns null without a prompt marker', () => {
  const buf = makeBuffer({ 0: '$ ls' }, 0, 0, 4);
  assert.equal(readInput(buf, null), null);
});

test('readInput extracts text between prompt marker and cursor', () => {
  // prompt occupies "myrepo $ " (9 chars), user typed "git st"
  const buf = makeBuffer({ 0: 'myrepo $ git st' }, 0, 0, 15);
  const marker = { baseY: 0, cursorY: 0, cursorX: 9, generation: 1 };
  const input = readInput(buf, marker);
  assert.equal(input.text, 'git st');
  assert.equal(input.cursor, 6);
});

test('readInput returns null when cursor is above the prompt (stale marker)', () => {
  const buf = makeBuffer({ 0: 'old', 1: 'prompt ' }, 0, 0, 2);
  const marker = { baseY: 0, cursorY: 1, cursorX: 7, generation: 1 };
  assert.equal(readInput(buf, marker), null);
});

test('handleKey passes through when menu is hidden', () => {
  assert.deepEqual(handleKey({ name: 'Tab' }, false, TabMode.NAVIGATION), { type: 'passthrough' });
  assert.deepEqual(handleKey({ name: 'Enter' }, false, TabMode.NAVIGATION), { type: 'passthrough' });
});

test('NAVIGATION mode: Tab/Shift-Tab navigate the menu', () => {
  assert.deepEqual(handleKey({ name: 'Tab' }, true, TabMode.NAVIGATION), { type: 'navigate', delta: 1 });
  assert.deepEqual(handleKey({ name: 'ShiftTab' }, true, TabMode.NAVIGATION), { type: 'navigate', delta: -1 });
});

test('DEFAULT mode: Tab passes through even with menu open', () => {
  assert.deepEqual(handleKey({ name: 'Tab' }, true, TabMode.DEFAULT), { type: 'passthrough' });
});

test('Enter accepts when menu visible; Escape closes', () => {
  assert.deepEqual(handleKey({ name: 'Enter' }, true, TabMode.NAVIGATION), { type: 'accept' });
  assert.deepEqual(handleKey({ name: 'Escape' }, true, TabMode.NAVIGATION), { type: 'close' });
});

test('arrows navigate when menu visible', () => {
  assert.deepEqual(handleKey({ name: 'Down' }, true, TabMode.DEFAULT), { type: 'navigate', delta: 1 });
  assert.deepEqual(handleKey({ name: 'Up' }, true, TabMode.DEFAULT), { type: 'navigate', delta: -1 });
});

test('moveSelection wraps around', () => {
  assert.equal(moveSelection(0, -1, 3), 2);
  assert.equal(moveSelection(2, 1, 3), 0);
  assert.equal(moveSelection(0, 1, 0), 0);
});
