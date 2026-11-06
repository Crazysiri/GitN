'use strict';

// Pure suggestion-menu logic (no DOM, no xterm) so it can be unit-tested.
// The DOM rendering and xterm buffer reading live in entry.js.

// Tab modes per SPEC §7.3.
const TabMode = {
  DEFAULT: 'DEFAULT',
  ENTER: 'ENTER',
  NAVIGATION: 'NAVIGATION',
};

/**
 * Read the current input line from the terminal buffer between the recorded
 * prompt marker and the cursor. Returns null when there is no trustworthy
 * prompt (so suggestions stay disabled — never guess from a `$`/`%`).
 *
 * `buffer` is an abstraction with getLine(y) → { text, length } and cursor
 * coordinates, matching the subset of xterm's API we use.
 */
function readInput(buffer, marker) {
  if (!marker) return null;
  const promptAbsY = marker.baseY + marker.cursorY;
  const cursorAbsY = buffer.baseY + buffer.cursorY;
  // Only single-line prompts are supported for input extraction here; a cursor
  // above the prompt means the marker is stale.
  if (cursorAbsY < promptAbsY) return null;

  if (cursorAbsY === promptAbsY) {
    const line = buffer.getLine(promptAbsY);
    if (!line) return null;
    const start = marker.cursorX;
    const text = line.text.slice(start, buffer.cursorX);
    return { text, cursor: text.length };
  }

  // Multi-row input (wrapped): concatenate from the prompt row to the cursor.
  let text = '';
  for (let y = promptAbsY; y <= cursorAbsY; y += 1) {
    const line = buffer.getLine(y);
    if (!line) continue;
    const from = y === promptAbsY ? marker.cursorX : 0;
    const to = y === cursorAbsY ? buffer.cursorX : line.length;
    text += line.text.slice(from, to);
  }
  return { text, cursor: text.length };
}

/**
 * Compute how a key should be handled given the current menu + tab mode.
 * Returns an action the caller performs; this function has no side effects.
 *
 * key is a normalized descriptor: { name: 'Tab'|'ShiftTab'|'Enter'|'Escape'
 * |'Up'|'Down'|'Other' }.
 */
function handleKey(key, menuVisible, tabMode) {
  if (!menuVisible) {
    // No menu: Tab/Enter pass through to the shell unchanged.
    return { type: 'passthrough' };
  }
  switch (key.name) {
    case 'Up':
      return { type: 'navigate', delta: -1 };
    case 'Down':
      return { type: 'navigate', delta: 1 };
    case 'Escape':
      return { type: 'close' };
    case 'Enter':
      return { type: 'accept' };
    case 'Tab':
      if (tabMode === TabMode.NAVIGATION) return { type: 'navigate', delta: 1 };
      if (tabMode === TabMode.ENTER || tabMode === TabMode.DEFAULT) {
        // DEFAULT passes Tab to the shell; ENTER accepts on Tab.
        return tabMode === TabMode.ENTER ? { type: 'accept' } : { type: 'passthrough' };
      }
      return { type: 'passthrough' };
    case 'ShiftTab':
      if (tabMode === TabMode.NAVIGATION) return { type: 'navigate', delta: -1 };
      return { type: 'passthrough' };
    default:
      return { type: 'passthrough' };
  }
}

/** Clamp/advance a selected index with wraparound. */
function moveSelection(index, delta, count) {
  if (count <= 0) return 0;
  return (((index + delta) % count) + count) % count;
}

module.exports = { TabMode, readInput, handleKey, moveSelection };
