import { Terminal } from '@xterm/xterm';
import { FitAddon } from '@xterm/addon-fit';
import { WebLinksAddon } from '@xterm/addon-web-links';
import { WebglAddon } from '@xterm/addon-webgl';
import '@xterm/xterm/css/xterm.css';

const {
  decodeBase64ToBytes,
  encodeBytesToBase64,
  sanitizeSize,
  postEvent,
} = require('./bridge.cjs');
const {
  TabMode,
  readInput,
  handleKey,
  moveSelection,
} = require('./suggestions.cjs');
const { createSuggestionMenu } = require('./suggestion-menu.cjs');

// Native message handlers (see XtermHostView.swift).
function hostHandler() {
  return window.webkit && window.webkit.messageHandlers
    ? window.webkit.messageHandlers.gitnTerminal
    : undefined;
}

const encoder = new TextEncoder();
const bridgeDeps = {
  atob: (value) => window.atob(value),
  btoa: (value) => window.btoa(value),
  String: window.String,
  Uint8Array: window.Uint8Array,
};

const state = {
  term: null,
  fit: null,
  webgl: null,
  isReady: false,
  lastCols: 0,
  lastRows: 0,
  promptMarker: null,
  menu: null,
  tabMode: TabMode.NAVIGATION,
  inputRevision: 0,
  isComposing: false,     // IME composition in progress
  inAlternateScreen: false,
  lastSentLine: null,
  suggestionsEnabled: true,
};

function applyTheme(isDark) {
  // Keep colors driven by the host's light/dark decision. Values map to the
  // standard macOS text colors the SwiftTerm panel used, so the switch is subtle.
  const dark = {
    background: '#1e1e1e',
    foreground: '#e0e0e0',
    cursor: '#e0e0e0',
    selectionBackground: '#3a5f8a',
  };
  const light = {
    background: '#ffffff',
    foreground: '#1a1a1a',
    cursor: '#1a1a1a',
    selectionBackground: '#b3d7ff',
  };
  const theme = isDark ? dark : light;
  // Paint every layer the same color so any partial row below the last line
  // (and xterm's own viewport/screen) blends in instead of showing a black band.
  document.documentElement.style.background = theme.background;
  document.body.style.background = theme.background;
  const container = document.getElementById('terminal');
  if (container) container.style.background = theme.background;
  // xterm paints its own viewport/screen; force them to the theme too.
  document.querySelectorAll('.xterm, .xterm-viewport, .xterm-screen').forEach((el) => {
    el.style.background = theme.background;
  });
  return theme;
}

function createTerminal(options) {
  const term = new Terminal({
    fontFamily: options.fontFamily || 'Menlo, Monaco, monospace',
    fontSize: options.fontSize || 12,
    lineHeight: options.lineHeight || 1.2,
    cursorStyle: options.cursorStyle || 'bar',
    cursorBlink: true,
    scrollback: options.scrollback || 5000,
    allowProposedApi: true,
    macOptionIsMeta: true,
    theme: applyTheme(options.isDark),
  });

  const fit = new FitAddon();
  term.loadAddon(fit);
  term.loadAddon(new WebLinksAddon((event, uri) => {
    // Links are opened by the native allowlist, never navigated in-page.
    event.preventDefault();
    postEvent(hostHandler(), 'openLink', { uri });
  }));

  const container = document.getElementById('terminal');
  term.open(container);
  // Now that xterm's DOM exists, paint its layers to the theme background so no
  // sub-row strip of a different color shows below the last rendered line.
  applyTheme(options.isDark);

  // Prompt tracking foundation: the opt-in shell wrapper emits CSI 7000 ~ at
  // the end of each prompt. Record the cursor position so suggestions (M3) know
  // where user input begins. Returning true marks the sequence as handled so it
  // is not rendered. This never fires without the wrapper installed.
  term.parser.registerCsiHandler({ final: '~' }, (params) => {
    // params[0] may be a number or a sub-param array; normalize.
    const first = Array.isArray(params[0]) ? params[0][0] : params[0];
    if (first === 7000) {
      const buffer = term.buffer.active;
      state.promptMarker = {
        baseY: buffer.baseY,
        cursorY: buffer.cursorY,
        cursorX: buffer.cursorX,
        generation: (state.promptMarker ? state.promptMarker.generation : 0) + 1,
      };
      postEvent(hostHandler(), 'prompt', state.promptMarker);
      return true;
    }
    return false; // let other `~` sequences (e.g. F-keys) pass to default
  });

  // WebGL is preferred; fall back silently to the DOM renderer on failure or
  // context loss so the terminal stays usable (CORE-10).
  let webgl = null;
  try {
    webgl = new WebglAddon();
    webgl.onContextLoss(() => {
      webgl.dispose();
      state.webgl = null;
    });
    term.loadAddon(webgl);
  } catch (error) {
    webgl = null;
    postEvent(hostHandler(), 'debug', { message: 'WebGL unavailable', detail: String(error) });
  }

  // File drag-and-drop is handled natively in XtermWebView (WKWebView does not
  // expose dropped-file paths to JS from a file:// page); the native side calls
  // window.gitnXterm.paste with the escaped paths.

  // Suggestion menu (DOM) attached to the terminal container.
  state.menu = createSuggestionMenu(document, container);
  state.menu.applyTheme(options.isDark);
  state.menu.setAcceptHandler((item) => acceptSuggestion(item));

  // Track alternate screen (vim/less/top): suppress suggestions entirely.
  term.buffer.onBufferChange((buffer) => {
    state.inAlternateScreen = buffer.type === 'alternate';
    if (state.inAlternateScreen) hideMenu();
  });

  // IME composition: never run suggestion key handling mid-composition.
  const textarea = term.textarea;
  if (textarea) {
    textarea.addEventListener('compositionstart', () => { state.isComposing = true; });
    textarea.addEventListener('compositionend', () => { state.isComposing = false; });
  }

  // Intercept menu-control keys before they reach the PTY. Returning false
  // stops xterm from sending the key. Only acts while the menu is visible and
  // we are at a trustworthy prompt; otherwise everything passes through.
  term.attachCustomKeyEventHandler((event) => {
    if (event.type !== 'keydown') return true;
    if (state.isComposing || state.inAlternateScreen) return true;
    const key = normalizeKey(event);
    if (key.name === 'Other') return true;

    const action = handleKey(key, state.menu.visible, state.tabMode);
    switch (action.type) {
      case 'passthrough':
        return true;
      case 'navigate':
        state.menu.move(action.delta);
        return false;
      case 'close':
        hideMenu();
        return false;
      case 'accept':
        if (state.menu.selectedItem) {
          acceptSuggestion(state.menu.selectedItem);
          return false;
        }
        return true;
      default:
        return true;
    }
  });

  // User input → native (as UTF-8 bytes, base64-encoded).
  term.onData((data) => {
    const bytes = encoder.encode(data);
    postEvent(hostHandler(), 'input', { bytes: encodeBytesToBase64(bytes, bridgeDeps) });
  });

  // After the renderer processes output/input, re-read the input line and ask
  // for suggestions. Debounced to one check per animation frame.
  let pending = false;
  const scheduleInputCheck = () => {
    if (pending) return;
    pending = true;
    // setTimeout rather than requestAnimationFrame: rAF may not fire reliably
    // in a backgrounded/offscreen WKWebView, which would stall suggestions.
    setTimeout(() => {
      pending = false;
      checkInput();
    }, 16);
  };
  term.onData(scheduleInputCheck);
  term.onCursorMove(scheduleInputCheck);
  // Also check after the PTY writes output (e.g. the prompt redraw after
  // backspace), so the marker/cursor state is re-read.
  term.onRender(scheduleInputCheck);

  // Binary input (mouse reporting etc.) preserves byte semantics.
  term.onBinary((data) => {
    const bytes = new Uint8Array(data.length);
    for (let i = 0; i < data.length; i += 1) bytes[i] = data.charCodeAt(i) & 0xff;
    postEvent(hostHandler(), 'input', { bytes: encodeBytesToBase64(bytes, bridgeDeps) });
  });

  term.onResize(({ cols, rows }) => {
    const size = sanitizeSize(cols, rows);
    if (size.cols === state.lastCols && size.rows === state.lastRows) return;
    state.lastCols = size.cols;
    state.lastRows = size.rows;
    postEvent(hostHandler(), 'resize', size);
  });

  term.onTitleChange((title) => {
    postEvent(hostHandler(), 'title', { title });
  });

  // Apply suggestion settings from the host.
  if (options.tabMode) window.gitnXterm.setTabMode(options.tabMode);
  state.suggestionsEnabled = options.suggestionsEnabled !== false;

  state.term = term;
  state.fit = fit;
  state.webgl = webgl;
  return term;
}

function fitNow() {
  if (!state.fit || !state.term) return;
  try {
    state.fit.fit();
  } catch (error) {
    postEvent(hostHandler(), 'debug', { message: 'fit failed', detail: String(error) });
  }
}

function normalizeKey(event) {
  if (event.key === 'Tab') return { name: event.shiftKey ? 'ShiftTab' : 'Tab' };
  if (event.key === 'Enter') return { name: 'Enter' };
  if (event.key === 'Escape') return { name: 'Escape' };
  if (event.key === 'ArrowUp') return { name: 'Up' };
  if (event.key === 'ArrowDown') return { name: 'Down' };
  return { name: 'Other' };
}

function hideMenu() {
  if (state.menu) state.menu.hide();
}

// Adapter exposing the subset of xterm's buffer that readInput needs.
function bufferAdapter() {
  const buffer = state.term.buffer.active;
  return {
    baseY: buffer.baseY,
    cursorY: buffer.cursorY,
    cursorX: buffer.cursorX,
    getLine(absY) {
      const line = buffer.getLine(absY);
      if (!line) return null;
      return { text: line.translateToString(true), length: line.length };
    },
  };
}

// Read the current input line and request suggestions, unless suppressed.
function checkInput() {
  if (!state.term || !state.menu) return;
  if (!state.suggestionsEnabled) { hideMenu(); return; }
  if (state.isComposing || state.inAlternateScreen) {
    hideMenu();
    return;
  }
  // No trustworthy prompt → disable suggestions (do not guess).
  if (!state.promptMarker) {
    hideMenu();
    return;
  }
  const input = readInput(bufferAdapter(), state.promptMarker);
  if (!input || input.text.length === 0) {
    hideMenu();
    state.lastSentLine = null;
    return;
  }
  if (input.text === state.lastSentLine) return;
  state.lastSentLine = input.text;
  state.inputRevision += 1;
  postEvent(hostHandler(), 'suggestRequest', {
    line: input.text,
    cursor: input.cursor,
    promptGeneration: state.promptMarker.generation,
    inputRevision: state.inputRevision,
  });
}

// Replace the active token in the shell by sending backspaces then the text.
// We only ever edit the active token; the replacement range came from Swift.
function acceptSuggestion(item) {
  if (!item || !state.term) return;
  const handler = hostHandler();
  // Delete the current prefix (item.prefixLength chars) then insert.
  const backspaces = '\u007f'.repeat(item.prefixLength || 0);
  const payload = backspaces + item.insertText;
  const bytes = encoder.encode(payload);
  postEvent(handler, 'input', { bytes: encodeBytesToBase64(bytes, bridgeDeps) });
  hideMenu();
  state.lastSentLine = null;
}

// Swift → JS imperative API.
window.gitnXterm = {
  start(optionsJSON) {
    try {
      const options = optionsJSON ? JSON.parse(optionsJSON) : {};
      if (!state.term) createTerminal(options);
      fitNow();
      state.term.focus();
      // Report the initial size so the PTY opens with the right winsize.
      const size = sanitizeSize(state.term.cols, state.term.rows);
      state.lastCols = size.cols;
      state.lastRows = size.rows;
      postEvent(hostHandler(), 'resize', size);
    } catch (error) {
      postEvent(hostHandler(), 'error', { message: 'start failed', detail: String(error) });
    }
  },

  // Raw PTY bytes (base64) → terminal. write() keeps byte boundaries intact so
  // multi-byte UTF-8 split across chunks is not corrupted (CORE-03).
  write(base64) {
    if (!state.term) return;
    try {
      const bytes = decodeBase64ToBytes(base64, bridgeDeps);
      state.term.write(bytes);
    } catch (error) {
      postEvent(hostHandler(), 'error', { message: 'write failed', detail: String(error) });
    }
  },

  setTheme(isDark) {
    if (!state.term) return;
    state.term.options.theme = applyTheme(isDark);
    if (state.menu) state.menu.applyTheme(isDark);
  },

  // Swift pushes suggestion results here. `prefixLength` is the number of
  // characters of the active token already typed (deleted on accept).
  showSuggestions(payloadJSON) {
    if (!state.term || !state.menu) return;
    try {
      const payload = JSON.parse(payloadJSON);
      // Drop stale results for a superseded input revision.
      if (payload.inputRevision !== state.inputRevision) return;
      if (state.isComposing || state.inAlternateScreen || !state.promptMarker) {
        hideMenu();
        return;
      }
      const items = (payload.suggestions || []).map((s) => ({
        displayName: s.displayName,
        detail: s.detail,
        insertText: s.insertText,
        prefixLength: payload.prefixLength || 0,
      }));
      const buffer = state.term.buffer.active;
      const cell = state.term.element
        ? state.term.element.querySelector('.xterm-cursor-layer')
        : null;
      // Position below the cursor row. Fall back to a fixed offset.
      const rowHeight = cell ? cell.clientHeight / state.term.rows : 18;
      const pos = {
        x: Math.max(4, buffer.cursorX * 7),
        y: (buffer.cursorY + 1) * (rowHeight || 18) + 4,
      };
      state.menu.show(items, pos);
    } catch (error) {
      postEvent(hostHandler(), 'error', { message: 'showSuggestions failed', detail: String(error) });
    }
  },

  setTabMode(mode) {
    if (mode === TabMode.DEFAULT || mode === TabMode.ENTER || mode === TabMode.NAVIGATION) {
      state.tabMode = mode;
    }
  },

  // Clipboard / selection actions, driven by the native context menu.
  hasSelection() {
    return !!(state.term && state.term.hasSelection());
  },

  getSelection() {
    return state.term ? state.term.getSelection() : '';
  },

  selectAll() {
    if (state.term) state.term.selectAll();
  },

  clearSelection() {
    if (state.term) state.term.clearSelection();
  },

  // Clear the screen (and scrollback) without restarting the shell.
  clear() {
    if (state.term) state.term.clear();
  },

  // Paste text as the user would: goes through onData → PTY, honoring the
  // shell's bracketed-paste mode. Never executed implicitly.
  paste(text) {
    if (state.term && typeof text === 'string') state.term.paste(text);
  },

  fit() {
    fitNow();
  },

  focus() {
    if (state.term) state.term.focus();
  },
};

window.addEventListener('resize', fitNow);
window.addEventListener('pagehide', () => {
  if (state.webgl) {
    state.webgl.dispose();
    state.webgl = null;
  }
  if (state.term) {
    state.term.dispose();
    state.term = null;
  }
});

// Signal readiness exactly once, after the DOM is in place.
function signalReady() {
  if (state.isReady) return;
  state.isReady = true;
  postEvent(hostHandler(), 'ready', {});
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', signalReady);
} else {
  signalReady();
}
