const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { buildUnifiedDiffModel } = require('../src/diff-model.cjs');

function host(debug = false) {
  const editors = [], models = [], requests = [], messages = [], nodes = [], diffs = [];
  class Node {
    constructor() {
      this.style = { setProperty() {} };
      this.classList = { toggle() {}, add() {}, contains() { return false; } };
      this.dataset = {};
      this.children = [];
      nodes.push(this);
    }
    appendChild(node) { this.children.push(node); }
    setAttribute(name, value) { this[name] = value; }
    addEventListener(name, callback) { (this.listeners ||= {})[name] = callback; }
    set innerHTML(value) { this.children = []; }
  }
  const root = new Node();
  const document = {
    body: new Node(), baseURI: 'file:///test/index.html',
    getElementById: () => root, createElement: () => new Node(),
    createTextNode: (value) => Object.assign(new Node(), { textContent: value }), addEventListener() {},
  };
  function createModel(value, language, uri) {
    const model = {
      value, uri, version: 1, disposed: false, setValueCalls: 0,
      getValue() { return this.value; },
      getVersionId() { return this.version; },
      getLineCount() { return this.value.split('\n').length; },
      setValue(value) { this.value = value; this.version += 1; this.setValueCalls += 1; this.onChange?.(); },
      getOptions: () => ({ tabSize: 4 }),
      dispose() { this.disposed = true; },
    };
    models.push(model);
    return model;
  }
  function create(node, options) {
    const editor = {
      model: options.model, options, change: () => {}, disposed: false, applied: 0,
      revealLineInCenter(line) { this.revealedLine = line; },
      getModel() { return this.model; }, getValue() { return this.model.value; },
      setModel(model) { this.model = model; this.change(); },
      onDidChangeModelContent(callback) { this.change = callback; },
      onDidScrollChange() {}, onDidLayoutChange() {},
      updateOptions(next) { this.options = Object.assign({}, this.options, next); }, addCommand() {},
      scrollTop: 0, scrollLeft: 0,
      saveViewState() { return { scrollTop: this.scrollTop, scrollLeft: this.scrollLeft }; },
      restoreViewState(state) { this.scrollTop = state.scrollTop; this.scrollLeft = state.scrollLeft; },
      setScrollPosition(position) {
        this.scrollTop = position.scrollTop ?? this.scrollTop;
        this.scrollLeft = position.scrollLeft ?? this.scrollLeft;
      },
      getScrollTop() { return this.scrollTop; }, getScrollLeft() { return this.scrollLeft; },
      getLayoutInfo: () => ({ contentLeft: 60, lineNumbersWidth: 40, lineDecorationsWidth: 12, height: 600 }),
      getOption(key) { return key === 'fontInfo' ? { fontSize: 12 } :
        key === 'lineNumbersMinChars' ? this.options.lineNumbersMinChars : 20; },
      getVisibleRanges: () => [],
      getTopForLineNumber: (line) => (line - 1) * 20,
      getScrollHeight: () => 600,
      deltaDecorations(old, next) { this.applied += next.length; return next.map((_, i) => '' + i); },
      zones: new Map(), hiddenAreas: [],
      changeViewZones(callback) {
        callback({ addZone: zone => { const id = 'zone-' + this.zones.size; this.zones.set(id, zone); return id; },
                   removeZone: id => this.zones.delete(id) });
      },
      setHiddenAreas(ranges) { this.hiddenAreas = ranges; },
      dispose() { this.disposed = true; },
    };
    editors.push(editor);
    return editor;
  }
  const window = {
    gitnHunkLayout: require('../src/hunk-layout.cjs'),
    gitnMonacoDebug: debug,
    atob: (value) => Buffer.from(value, 'base64').toString('binary'),
    btoa: (value) => Buffer.from(value, 'binary').toString('base64'),
    addEventListener() {}, cancelAnimationFrame() {}, requestAnimationFrame: () => 1,
    webkit: { messageHandlers: { monaco: { postMessage: (value) => messages.push(value) } } },
    monaco: {
      Uri: { parse: (value) => ({ scheme: 'gitn', path: value, toString: () => value }) },
      KeyMod: { CtrlCmd: 1 }, KeyCode: { KeyS: 1 }, Range: class { constructor(startLineNumber, startColumn, endLineNumber, endColumn) { Object.assign(this, {startLineNumber, startColumn, endLineNumber, endColumn}); } },
      editor: {
        createDiffEditor(node, options) {
          const original = create(node, {}), modified = create(node, {});
          const diff = {
            options, disposed: false, changes: null,
            onDidUpdateDiff(callback) { this.onUpdate = callback; },
            getLineChanges() { return this.changes; },
            updateDiff(changes) { this.changes = changes; this.onUpdate?.(); },
            setModel(pair) { original.model = pair.original; modified.model = pair.modified; },
            getOriginalEditor: () => original, getModifiedEditor: () => modified,
            goToDiff(direction) { this.direction = direction; },
            dispose() { this.disposed = true; original.dispose(); modified.dispose(); },
          };
          diffs.push(diff);
          return diff;
        },
        create, createModel, getModels: () => models.filter((m) => !m.disposed),
        getModel: (uri) => models.find((m) => !m.disposed && m.uri.toString() === uri.toString()),
        setTheme() {}, OverviewRulerLane: { Left: 1, Right: 2 },
        EditorOption: { fontInfo: 'fontInfo', lineHeight: 'lineHeight', lineNumbersMinChars: 'lineNumbersMinChars' },
      },
    },
    gitnDiffScheduler: {
      cancel() {},
      run(original, modified) {
        return new Promise((resolve, reject) => requests.push({ original, modified, resolve, reject }));
      },
    },
  };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../../Sources/GitN/Resources/Monaco/host.js'), 'utf8'),
    { window, document, console, setTimeout, clearTimeout, Map, Set });
  const load = (payload) => window.gitnMonaco.loadPayload(Buffer.from(JSON.stringify(payload)).toString('base64'));
  return { load, editors, models, requests, messages, nodes, diffs, navigate: window.gitnMonaco.navigateDiff };
}
const tick = () => new Promise((resolve) => setTimeout(resolve, 5));
const preview = (name, content) => ({ mode: 'preview', preview: { path: name, content, language: 'plaintext', isEditable: true } });
const diff = (name, content) => ({ mode: 'diff', items: [{
  path: name, originalText: 'old', modifiedText: content, language: 'plaintext', isEditable: true,
}] });

test('routine debug bridge traffic is opt-in', () => {
  const quiet = host();
  quiet.load(preview('a.txt', 'one'));
  assert.equal(quiet.messages.some((message) => message.event === 'debug'), false);
  const verbose = host(true);
  verbose.load(preview('a.txt', 'one'));
  assert.equal(verbose.messages.some((message) => message.event === 'debug'), true);
});

test('preview reuses editor, caches models and reports the new path on edit', () => {
  const h = host();
  h.load(preview('a.txt', 'one'));
  h.load(preview('b.txt', 'two'));
  assert.equal(h.editors.length, 1);
  assert.equal(h.models[0].disposed, false);
  assert.equal(h.editors[0].getValue(), 'two');
  const currentModel = h.editors[0].getModel();
  h.load(preview('b.txt', 'updated'));
  assert.equal(h.editors[0].getModel(), currentModel);
  assert.equal(h.editors[0].getValue(), 'updated');
  h.editors[0].model.value = 'edit';
  h.editors[0].change();
  assert.equal(h.messages.filter((m) => m.event === 'contentChanged').at(-1).path, 'b.txt');
});

test('revisiting a file preserves its model until authoritative text changes', () => {
  const h = host();
  h.load(preview('a.txt', 'one'));
  const original = h.editors[0].getModel();
  h.load(preview('b.txt', 'two'));
  h.load(preview('a.txt', 'one'));
  assert.equal(h.editors[0].getModel(), original);
  assert.equal(original.setValueCalls, 0);
  h.load(preview('b.txt', 'two'));
  h.load(preview('a.txt', 'new external content'));
  assert.equal(h.editors[0].getModel(), original);
  assert.equal(original.setValueCalls, 1);
  assert.equal(original.getValue(), 'new external content');
});

test('models are isolated by source identity and idle entries are evicted', () => {
  const h = host();
  const samePath = (sourceID) => ({ ...preview('a.txt', 'one'), sourceID });
  h.load(samePath('repo|stash-one'));
  const first = h.editors[0].getModel();
  h.load(samePath('repo|stash-two'));
  const second = h.editors[0].getModel();
  assert.notEqual(first, second);
  assert.equal(first.disposed, false);
  h.load(samePath('repo|stash-one'));
  assert.equal(h.editors[0].getModel(), first);
  for (let index = 0; index < 9; index += 1) {
    h.load(preview('file-' + index + '.txt', 'content'));
  }
  assert.equal(first.disposed, true);
  assert.ok(h.models.filter((model) => !model.disposed).length <= 8);
  assert.equal(h.editors[0].getModel().disposed, false);
});

test('same-path preview metadata update preserves the model and undo version', () => {
  const h = host();
  h.load(preview('a.txt', 'one'));
  const model = h.editors[0].getModel();
  h.load({ ...preview('a.txt', 'one'), preview: { ...preview('a.txt', 'one').preview, language: 'markdown' } });
  assert.equal(h.editors[0].getModel(), model);
  assert.equal(model.setValueCalls, 0);
  assert.equal(model.getVersionId(), 1);
  h.load(preview('a.txt', 'two'));
  assert.equal(model.getValue(), 'two');
  assert.equal(model.setValueCalls, 1);
});

test('same-path diff metadata update preserves the modified model and undo version', () => {
  const h = host();
  h.load(diff('a.txt', 'one'));
  const model = h.editors[0].getModel();
  const changed = diff('a.txt', 'one');
  changed.items[0].originalText = 'different baseline';
  h.load(changed);
  assert.equal(h.editors[0].getModel(), model);
  assert.equal(model.setValueCalls, 0);
  assert.equal(model.getVersionId(), 1);
  h.load(diff('a.txt', 'two'));
  assert.equal(model.getValue(), 'two');
  assert.equal(model.setValueCalls, 1);
});

test('file switches restore each file’s scroll position in preview and diff', () => {
  for (const makePayload of [preview, diff]) {
    const h = host();
    h.load(makePayload('a.txt', 'one'));
    const editor = h.editors[0];
    editor.setScrollPosition({ scrollTop: 320, scrollLeft: 18 });
    h.load(makePayload('b.txt', 'two'));
    assert.equal(editor.getScrollTop(), 0);
    editor.setScrollPosition({ scrollTop: 140, scrollLeft: 4 });
    h.load(makePayload('a.txt', 'one'));
    assert.equal(editor.getScrollTop(), 320);
    assert.equal(editor.getScrollLeft(), 18);
    h.load(makePayload('b.txt', 'two'));
    assert.equal(editor.getScrollTop(), 140);
    assert.equal(editor.getScrollLeft(), 4);
  }
});

test('switching diff files preserves two readable number columns', () => {
  const h = host();
  h.load(diff('a.txt', 'one'));
  assert.equal(h.editors[0].options.lineNumbersMinChars, 10);
  h.load(diff('b.txt', 'two'));
  assert.equal(h.editors[0].options.lineNumbersMinChars, 10);
  const large = Array.from({ length: 10000 }, (_, i) => 'line ' + i).join('\n');
  h.load(diff('large.txt', large));
  assert.equal(h.editors[0].options.lineNumbersMinChars, 12);
});

test('rapid diff edits schedule only the latest worker request', async () => {
  const h = host();
  h.load(diff('a.txt', 'one'));
  await tick();
  assert.equal(h.requests.length, 1);
  const editor = h.editors[0];
  editor.model.value = 'two';
  editor.change();
  editor.model.value = 'three';
  editor.change();
  assert.equal(h.requests.length, 1);
  await new Promise((resolve) => setTimeout(resolve, 175));
  assert.equal(h.requests.length, 2);
  assert.equal(h.requests[1].modified, 'three');
});

test('diff renders text first, metadata does not restart work, stale results cannot decorate a new file', async () => {
  const h = host();
  h.load(diff('a.txt', 'first'));
  assert.equal(h.editors[0].getValue(), 'first');
  assert.equal(h.requests.length, 0);
  await tick();
  h.load(diff('a.txt', 'first'));
  assert.equal(h.requests.length, 1);
  h.load(diff('b.txt', 'second'));
  await tick();
  assert.equal(h.editors.length, 1);
  assert.equal(h.models[0].disposed, false);
  h.requests[0].resolve({ additionDecorations: [{ startLineNumber: 1, endLineNumber: 1 }] });
  await tick();
  assert.equal(h.editors[0].applied, 0);
  h.requests[1].reject(new Error('Diff computation timed out. Text remains available.'));
  await tick();
  assert.equal(h.editors[0].getValue(), 'second');
  assert.ok(h.nodes.some((node) => node.textContent?.includes('timed out') && !node.hidden));
});

test('diff renders a red deletion zone and the removed text', async () => {
  const h = host();
  h.load({ mode: 'diff', isDark: true, items: [{
    path: 'removed.md', originalText: 'keep\nremoved red line\n', modifiedText: 'keep\n',
    language: 'markdown', isEditable: false,
  }] });
  await tick();
  assert.equal(h.requests.length, 1);
  h.requests[0].resolve(buildUnifiedDiffModel('keep\nremoved red line\n', 'keep\n'));
  await tick();
  assert.ok(h.nodes.some((node) => node.className === 'gitn-deletion-content-block'));
  assert.ok(h.nodes.some((node) => node.className === 'gitn-deletion-line-content' &&
    node.textContent === 'removed red line'));
  assert.ok(h.nodes.some((node) => node.className === 'gitn-diff-status' && node.hidden));
});


test('Hunk disables native folding, Split stays side by side and navigation uses native diff', () => {
  const h = host();
  h.load({ ...diff('a.txt', 'new'), diffDisplay: 'hunk' });
  assert.equal(h.diffs.length, 1);
  assert.equal(h.diffs[0].options.renderSideBySide, false);
  assert.equal(h.diffs[0].options.hideUnchangedRegions.enabled, false);
  assert.equal(h.diffs[0].options.hideUnchangedRegions.contextLineCount, 3);
  h.load({ ...diff('a.txt', 'new'), diffDisplay: 'split' });
  assert.equal(h.diffs[0].disposed, true);
  assert.equal(h.diffs[1].options.renderSideBySide, true);
  assert.equal(h.diffs[1].options.useInlineViewWhenSpaceIsLimited, false);
  assert.equal(h.diffs[1].options.originalEditable, false);
  assert.equal(h.diffs[1].options.hideUnchangedRegions.enabled, false);
  assert.equal(h.requests.length, 0, 'no duplicate custom diff calculation');
  h.navigate('next');
  assert.equal(h.diffs[1].direction, 'next');
  h.navigate('prev');
  assert.equal(h.diffs[1].direction, 'previous');
  assert.deepEqual(h.messages.filter(m => m.event === 'error'), []);
});

test('native edit reports modified content, metadata preserves editor and layouts retain text', () => {
  const h = host();
  const payload = { ...diff('edit.txt', 'new'), diffDisplay: 'split' };
  h.load(payload);
  const native = h.diffs[0];
  native.getModifiedEditor().getModel().setValue('unsaved');
  native.getModifiedEditor().change();
  const message = h.messages.find(m => m.event === 'contentChanged');
  assert.equal(message.path, 'edit.txt');
  assert.equal(Buffer.from(message.content, 'base64').toString(), 'unsaved');
  payload.items[0].modifiedText = 'unsaved';
  h.load(payload);
  assert.equal(h.diffs.length, 1);
  h.load({ ...payload, diffDisplay: 'hunk' });
  assert.equal(h.diffs[1].getModifiedEditor().getValue(), 'unsaved');
  h.load({ ...payload, diffDisplay: 'inline' });
  assert.equal(h.diffs[1].disposed, true);
  assert.equal(h.editors.at(-1).getValue(), 'unsaved');
  assert.deepEqual(h.messages.filter(m => m.event === 'error'), []);
});

test('native Git actions use patch hunk identities and disappear immediately on edit', () => {
  const h = host();
  const payload = { ...diff('delete.txt', ''), diffDisplay: 'split' };
  payload.items[0].primaryHunkAction = 'stage';
  payload.items[0].showsDiscardAction = true;
  payload.items[0].hunkControls = [{
    hunkIndex: 7, lineIDs: [11], anchorKind: 'deletion', oldStartLine: 2,
  }];
  h.load(payload);
  const button = h.nodes.find(n => n.className === 'gitn-hunk-action gitn-hunk-action-stage');
  assert.ok(button);
  button.listeners.click({ preventDefault() {}, stopPropagation() {} });
  const action = h.messages.find(m => m.event === 'hunkAction');
  assert.equal(action.hunkIndex, 7);
  assert.equal(action.path, 'delete.txt');
  assert.deepEqual(Array.from(action.lineIDs), []);
  const bar = h.nodes.find(n => n.className === 'gitn-native-actions');
  h.diffs[0].getModifiedEditor().getModel().setValue('edited');
  h.diffs[0].getModifiedEditor().change();
  assert.equal(bar.hidden, true);
  assert.deepEqual(h.messages.filter(m => m.event === 'error'), []);
});

test('native deleted-only and added-only models survive preview transitions and invalid preference', () => {
  const h = host();
  for (const [oldText, newText] of [['deleted', ''], ['', 'added'], ['', '']]) {
    const payload = diff('file.txt', newText);
    payload.items[0].originalText = oldText;
    h.load({ ...payload, diffDisplay: 'hunk' });
    const native = h.diffs.at(-1);
    assert.equal(native.getOriginalEditor().getValue(), oldText);
    assert.equal(native.getModifiedEditor().getValue(), newText);
    h.load(preview('file.txt', 'preview'));
    assert.equal(native.disposed, true);
  }
  h.load({ ...diff('file.txt', 'inline'), diffDisplay: 'invalid' });
  assert.equal(h.editors.at(-1).getValue(), 'inline');
  assert.deepEqual(h.messages.filter(m => m.event === 'error'), []);
});


test('Hunk renders separate range headers with cropped gaps and per-block Git actions', () => {
  const h = host();
  const lines = Array.from({length: 60}, (_, i) => 'line ' + (i + 1)).join('\n');
  const payload = { ...diff('sections.txt', lines.replace('line 10', 'new 10').replace('line 40', 'new 40')), diffDisplay: 'hunk' };
  payload.items[0].originalText = lines;
  payload.items[0].primaryHunkAction = 'stage';
  payload.items[0].hunkControls = [
    {hunkIndex: 3, newStartLine: 10, newEndLine: 10, anchorKind: 'addition'},
    {hunkIndex: 8, newStartLine: 40, newEndLine: 40, anchorKind: 'addition'},
  ];
  h.load(payload);
  const native = h.diffs[0];
  native.updateDiff([10, 40].map(line => ({ originalStartLineNumber: line,
    originalEndLineNumber: line, modifiedStartLineNumber: line, modifiedEndLineNumber: line })));
  const editor = native.getModifiedEditor();
  const headers = [...editor.zones.values()].map(zone => zone.domNode);
  assert.equal(headers.length, 2);
  assert.equal(headers[0].children[0].textContent, '@@ -7,7 +7,7 @@');
  assert.equal(headers[1].children[0].textContent, '@@ -37,7 +37,7 @@');
  assert.deepEqual(editor.hiddenAreas.map(r => [r.startLineNumber, r.endLineNumber]), [[1,6],[14,36],[44,60]]);
  const stages = headers.map(header => header.children[1].children[0].children[0]);
  stages[1].listeners.click({preventDefault() {}, stopPropagation() {}});
  assert.equal(h.messages.find(m => m.event === 'hunkAction').hunkIndex, 8);
  assert.equal(h.nodes.find(n => n.className === 'gitn-native-actions').hidden, true);
  payload.items[0].hunkControls = [];
  h.load(payload);
  assert.equal(h.diffs.length, 1, 'metadata preserves the editor');
  assert.equal(editor.zones.size, 2, 'metadata replaces headers without accumulating zones');
  assert.ok([...editor.zones.values()].every(zone => zone.domNode.children.length === 1));
  assert.deepEqual(h.messages.filter(m => m.event === 'error'), []);
});
