/* Three Monaco surfaces over a stable structural diff3 document. No native scroll bridge. */
(function (global) {
  const clamp = (value, min, max) => Math.min(max, Math.max(min, value));
  function mapOffset(offset, source, target) {
    if (!source.length || source.length !== target.length) return 0;
    let index = source.findIndex(segment => offset < segment[1]);
    if (index < 0) index = source.length - 1;
    const [start, end] = source[index], [toStart, toEnd] = target[index];
    return toStart + clamp((offset - start) / Math.max(end - start, 1), 0, 1) * (toEnd - toStart);
  }
  function segments(blocks, side, lineCount) {
    const result = []; let cursor = 0;
    for (const block of blocks) {
      // Deleted chunks stay at their insertion point; don't discard zero-length anchors.
      const start = clamp(block[side][0], cursor, lineCount);
      const end = clamp(block[side][1], start, lineCount);
      result.push([cursor, start], [start, end]); cursor = end;
    }
    result.push([cursor, lineCount]); return result;
  }
  function compactGeometry(blocks, side, lineCount, lineHeight = 19, headerHeight = 25) {
    let top = 0;
    return segments(blocks, side, lineCount).map(([start, end], index) => {
      const height = (end - start) * lineHeight + (index % 2 ? headerHeight : 0);
      const interval = [top, top + height]; top += height;
      return interval;
    });
  }
  if (typeof module !== 'undefined') module.exports = { mapOffset, segments, compactGeometry };
  if (!global.document) return;

  let state = null;
  const sides = ['ours', 'theirs', 'output'];
  const lineHeight = 19, headerHeight = 25;
  const encode = text => global.btoa(unescape(encodeURIComponent(text)));
  function post(event, detail = {}) {
    if (!state) return;
    global.webkit?.messageHandlers?.monaco?.postMessage({ event, sourceID: state.sourceID,
      path: state.payload.path, editRevision: state.editRevision, ...detail });
  }
  function action(action, block = -1, line) {
    post('hunkAction', { action, hunkIndex: block, lineIDs: line === undefined ? [] : [line] });
  }
  function button(label, callback, selected = false) {
    const el = document.createElement('button'); el.textContent = label;
    el.className = 'gitn-merge-button'; el.setAttribute('aria-pressed', String(selected));
    el.addEventListener('click', callback); return el;
  }
  function dispose() {
    if (!state) return;
    if (state.frame !== null) cancelAnimationFrame(state.frame);
    state.observer.disconnect();
    for (const disposable of state.disposables) disposable.dispose();
    for (const side of sides) { state.editors[side].dispose(); state.models[side].dispose(); }
    state.shell.remove(); state = null;
  }
  function create(payload, sourceID) {
    dispose();
    const shell = document.createElement('div'); shell.className = 'gitn-merge-shell';
    const root = document.getElementById('root');
    root.className = 'root';
    root.replaceChildren(shell);
    state = { payload, sourceID, shell, models: {}, editors: {}, zones: {}, decorations: {}, geometry: {},
      metadataKeys: {},
      disposables: [], editRevision: 0, applying: false, syncing: false, frame: null,
      driver: null, navigationID: null, observer: null };
    for (const side of sides) {
      const panel = document.createElement('section'); panel.className = `gitn-merge-panel gitn-merge-${side}`;
      const heading = document.createElement('header');
      if (side !== 'output') heading.append(button('Select all', () => action(side === 'ours' ? 'allOurs' : 'allTheirs')));
      const title = document.createElement('span'); title.className = 'gitn-merge-title';
      title.textContent = side === 'output' ? 'Output' : `${side === 'ours' ? 'A' : 'B'} · ${payload[side + 'Label']}`;
      heading.append(title); panel.append(heading);
      const container = document.createElement('div'); container.className = 'gitn-merge-editor'; panel.append(container);
      shell.append(panel);
      const model = monaco.editor.createModel(payload[side + 'Text'], payload.language,
        monaco.Uri.parse(`gitn-merge://${side}/${encodeURIComponent(sourceID)}/${encodeURIComponent(payload.path)}`));
      const editor = monaco.editor.create(container, { model, automaticLayout: false, readOnly: side !== 'output',
        fontSize: 12, lineHeight, padding: {top: 0, bottom: 0}, minimap: {enabled: false},
        folding: false, stickyScroll: {enabled: false}, glyphMargin: true,
        lineNumbersMinChars: 4, wordWrap: 'off',
        scrollBeyondLastLine: false, renderLineHighlight: 'line', roundedSelection: false,
        fixedOverflowWidgets: true, contextmenu: true });
      state.models[side] = model; state.editors[side] = editor; state.zones[side] = [];
      state.disposables.push(editor.onDidScrollChange(event => {
        if (state.applying || state.syncing || (!event.scrollTopChanged && !event.scrollLeftChanged)) return;
        state.driver = side;
        if (state.frame !== null) return;
        state.frame = requestAnimationFrame(() => {
          if (!state) return;
          state.frame = null;
          try { synchronize(state.driver); }
          catch (error) { post('error', {message: String(error), detail: error?.stack || ''}); }
        });
      }));
      if (side !== 'output') state.disposables.push(editor.onMouseDown(event => {
        if (event.target.type !== monaco.editor.MouseTargetType.GUTTER_GLYPH_MARGIN || !event.target.position) return;
        const row = event.target.position.lineNumber - 1;
        const block = state.payload.blocks.find(block => row >= block[side][0] && row < block[side][1]);
        if (block) action(side + 'Line', block.id, row - block[side][0]);
      }));
    }
    const output = state.editors.output;
    state.disposables.push(output.onDidChangeModelContent(() => {
      if (state.applying) return;
      state.editRevision++;
      post('contentChanged', { content: encode(output.getValue()) });
    }));
    // Shadow Monaco's model-only undo in the output editor: keyboard, editor
    // actions, and context menu all use the same native document undo stack.
    output.addAction({ id: 'undo', label: 'Undo Merge Edit', contextMenuGroupId: '1_modification',
      contextMenuOrder: 0, keybindings: [monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyZ],
      run: () => action('undo') });
    output.addAction({ id: 'redo', label: 'Redo Merge Edit', contextMenuGroupId: '1_modification',
      contextMenuOrder: 1, keybindings: [monaco.KeyMod.CtrlCmd | monaco.KeyMod.Shift | monaco.KeyCode.KeyZ,
        monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyY], run: () => action('redo') });
    output.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, () => post('saveRequest'));
    addSplitter('vertical'); addSplitter('horizontal');
    state.observer = new ResizeObserver(() => {
      if (!state) return;
      state.syncing = true;
      try { for (const side of sides) state.editors[side].layout(); }
      catch (error) { post('error', {message: String(error), detail: error?.stack || ''}); }
      finally { state.syncing = false; }
    });
    state.observer.observe(shell);
  }
  function addSplitter(direction) {
    const splitter = document.createElement('div'); splitter.className = `gitn-merge-splitter ${direction}`;
    splitter.setAttribute('role', 'separator'); splitter.setAttribute('aria-orientation', direction);
    state.shell.append(splitter);
    splitter.addEventListener('pointerdown', event => {
      splitter.setPointerCapture(event.pointerId); event.preventDefault();
      const move = e => {
        const rect = state.shell.getBoundingClientRect();
        if (direction === 'vertical') state.shell.style.setProperty('--merge-left', `${clamp((e.clientX - rect.x) / rect.width * 100, 20, 80)}%`);
        else state.shell.style.setProperty('--merge-top', `${clamp((e.clientY - rect.y) / rect.height * 100, 25, 75)}%`);
        for (const side of sides) state.editors[side].layout();
      };
      const up = () => { splitter.removeEventListener('pointermove', move); splitter.removeEventListener('pointerup', up); };
      splitter.addEventListener('pointermove', move); splitter.addEventListener('pointerup', up);
    });
  }
  function synchronize(driver) {
    if (!state.geometry[driver]) return;
    const editor = state.editors[driver];
    const center = editor.getScrollTop() + editor.getLayoutInfo().height / 2;
    state.syncing = true;
    try {
      for (const side of sides) {
        if (side === driver) continue;
        const target = state.editors[side];
        target.setScrollPosition({ scrollTop: Math.max(0, mapOffset(center, state.geometry[driver], state.geometry[side])
          - target.getLayoutInfo().height / 2), scrollLeft: editor.getScrollLeft() }, monaco.editor.ScrollType.Immediate);
      }
    } finally { state.syncing = false; }
  }
  function updateMetadata() {
    const payload = state.payload;
    for (const side of sides) {
      const editor = state.editors[side], model = state.models[side], decorations = [];
      const metadataKey = JSON.stringify({ lineCount: model.getLineCount(),
        blocks: payload.blocks.map(block => side === 'output'
          ? [block.output, block.resolved]
          : [block[side], block['selected' + (side === 'ours' ? 'Ours' : 'Theirs')],
            block['all' + (side === 'ours' ? 'Ours' : 'Theirs')]]),
        origins: side === 'output' ? payload.origins : null });
      if (state.metadataKeys[side] === metadataKey) continue;
      const ranges = segments(payload.blocks, side, model.getLineCount());
      const geometry = compactGeometry(payload.blocks, side, model.getLineCount(), lineHeight, headerHeight);
      editor.changeViewZones(accessor => {
        state.zones[side].forEach(id => accessor.removeZone(id)); state.zones[side] = [];
        for (let index = 0; index < ranges.length; index++) {
          const [start, end] = ranges[index];
          if (index % 2 === 0) continue;
          const block = payload.blocks[(index - 1) / 2];
          const header = document.createElement('div'); header.className = 'gitn-merge-block-header';
          header.dataset.block = block.id;
          if (side !== 'output') {
            const checked = side === 'ours' ? block.allOurs : block.allTheirs;
            const label = (start === end ? 'Take empty ' : 'Take ') + (side === 'ours' ? 'A' : 'B') +
              (start === end ? '' : ' block');
            const toggle = button(label, () => action(side, block.id), checked);
            toggle.classList.add('gitn-merge-block-toggle'); header.append(toggle);
          } else header.textContent = `${block.resolved ? '✓' : '●'} Conflict ${block.id + 1}${block.resolved ? '' : ' · unresolved'}`;
          state.zones[side].push(accessor.addZone({ afterLineNumber: start, heightInPx: headerHeight,
            domNode: header, suppressMouseDown: false }));
          for (let line = start; line < end; line++) {
            const selected = side === 'output' ? false : (side === 'ours' ? block.selectedOurs : block.selectedTheirs).includes(line - start);
            decorations.push({range: new monaco.Range(line + 1, 1, line + 1, 1), options: {
              isWholeLine: true, className: `gitn-merge-line ${side} ${selected ? 'selected' : ''}`,
              glyphMarginClassName: side === 'output' ? undefined : `gitn-merge-glyph ${selected ? 'selected' : ''}`,
              glyphMarginHoverMessage: {value: selected ? 'Remove this source line' : 'Append this source line to output'} }});
          }
        }
      });
      if (side === 'output') payload.origins.forEach((origin, line) => {
        if (origin !== 'common') decorations.push({range: new monaco.Range(line + 1, 1, line + 1, 1),
          options: {isWholeLine: true, linesDecorationsClassName: `gitn-merge-origin ${origin}`}});
      });
      state.geometry[side] = geometry;
      state.decorations[side] = editor.deltaDecorations(state.decorations[side] || [], decorations);
      state.metadataKeys[side] = metadataKey;
    }
  }
  function load(payload, sourceID) {
    if (!state || state.sourceID !== sourceID || state.payload.path !== payload.path) create(payload, sourceID);
    // A payload acknowledges exactly the edit revision processed by Swift. Never
    // let an older callback roll back more recent local typing (or its geometry).
    if (payload.acknowledgedEdit < state.editRevision) return;
    const previousNavigation = state.navigationID;
    state.payload = payload; state.applying = true;
    try {
      const model = state.models.output;
      if (model.getValue() !== payload.outputText) {
        const selection = state.editors.output.getSelection(), scroll = state.editors.output.getScrollTop();
        model.applyEdits([{range: model.getFullModelRange(), text: payload.outputText}]);
        if (selection) state.editors.output.setSelection(selection);
        state.editors.output.setScrollTop(scroll);
      }
      updateMetadata();
      state.navigationID = payload.navigationID;
      if (previousNavigation !== payload.navigationID && payload.blocks.length) {
        const block = payload.blocks[clamp(payload.currentBlock, 0, payload.blocks.length - 1)];
        for (const side of sides) {
          const index = payload.blocks.indexOf(block) * 2 + 1;
          state.editors[side].setScrollTop(Math.max(0, state.geometry[side][index][0] - lineHeight * 2));
        }
      }
    } finally { state.applying = false; }
  }
  global.gitnConflict = { load, dispose };
  global.addEventListener('pagehide', dispose);
})(typeof window === 'undefined' ? globalThis : window);
