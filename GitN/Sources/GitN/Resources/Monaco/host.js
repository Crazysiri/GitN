(function () {
  const state = {
    editors: [],
    currentMode: null,
    isReady: false,
    diffEditor: null,
    nativeDiff: null,
    diffDisplay: "inline",
    nativeActions: null,
    nativeItem: null,
    nativeHunkZones: { original: [], modified: [] },
    nativeLabels: null,
    nativeNode: null,
    diffModel: null,
    diffDecorations: [],
    diffZoneIds: [],
    zoneResizeObserver: null,
    gutterOverlay: null,
    contentOverlay: null,
    pendingHunkActions: null,
    pendingLineBlames: null,
    tooltipElement: null,
    activeTooltipKey: null,
    currentHunkIndex: -1,
    currentDiffIdentity: null,
    currentPreviewIdentity: null,
    currentEditorPath: null,
    currentEditorSourceID: null,
    currentSourceID: "",
    modelCache: new Map(),
    pendingViewState: null,
    viewStates: new Map(),
    pendingGutterAnimationFrame: null,
    diffGeneration: 0,
    diffTimer: null,
    diffStatus: null,
    currentDiffOriginalText: "",
    currentDiffLanguage: "plaintext",
    currentDiffEditable: false,
    currentPreviewLanguage: "plaintext",
    currentPreviewEditable: false,
    isReplacingModel: false,
  };
  

  function decodeBase64(value) {
    try {
      return decodeURIComponent(escape(window.atob(value)));
    } catch (_) {
      return window.atob(value);
    }
  }

  function encodeBase64(value) {
    try {
      return window.btoa(unescape(encodeURIComponent(value)));
    } catch (_) {
      return window.btoa(value);
    }
  }

  function postMessage(event, payload) {
    if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.monaco) {
      return;
    }
    window.webkit.messageHandlers.monaco.postMessage(Object.assign({ event }, payload || {}));
  }

  function reportError(message, detail) {
    postMessage("error", {
      message: String(message || "Unknown Monaco host error"),
      detail: detail ? String(detail) : "",
    });
  }

  function reportDebug(message, payload) {
    if (!window.gitnMonacoDebug) return;
    postMessage("debug", {
      message: String(message || ""),
      detail: payload ? JSON.stringify(payload) : "",
    });
  }

  function editorOptions(isEditable) {
    return {
      automaticLayout: true,
      fontSize: 12,
      folding: false,
      minimap: { enabled: false },
      scrollBeyondLastLine: false,
      showFoldingControls: "never",
      roundedSelection: false,
      readOnly: !isEditable,
      wordWrap: "off",
      lineNumbersMinChars: 4,
    };
  }

  function diffLineNumberMinChars(lineCount) {
    const digits = String(Math.max(1, lineCount || 1)).length;
    return Math.max(10, digits * 2 + 2);
  }

  function formatLineNumber(value) {
    return typeof value === "number" ? String(value) : "";
  }

  function getLineNumberEntry(lineNumber) {
    if (!state.diffModel || !state.diffModel.lineNumberMap) {
      return null;
    }
    return state.diffModel.lineNumberMap.get(lineNumber) || null;
  }

  function disposeAllEditors() {
    state.diffGeneration += 1;
    if (state.diffTimer !== null) {
      clearTimeout(state.diffTimer);
      state.diffTimer = null;
    }
    if (window.gitnDiffScheduler) {
      window.gitnDiffScheduler.cancel();
    }
    if (state.pendingGutterAnimationFrame !== null) {
      try {
        window.cancelAnimationFrame(state.pendingGutterAnimationFrame);
      } catch (_) {}
      state.pendingGutterAnimationFrame = null;
    }
    if (state.zoneResizeObserver) {
      try {
        state.zoneResizeObserver.disconnect();
      } catch (_) {}
      state.zoneResizeObserver = null;
    }
    if (state.nativeDiff) {
      state.nativeDiff.dispose();
      state.nativeDiff = null;
      state.editors = [];
    }
    state.nativeActions = null;
    state.nativeItem = null;
    state.nativeLabels = null;
    state.nativeNode = null;
    state.nativeHunkZones = { original: [], modified: [] };
    for (const editor of state.editors) {
      try {
        editor.dispose();
      } catch (_) {}
    }
    state.editors = [];
    state.diffEditor = null;
    state.diffModel = null;
    state.diffDecorations = [];
    state.diffZoneIds = [];
    state.gutterOverlay = null;
    state.contentOverlay = null;
    state.diffStatus = null;
    state.currentDiffIdentity = null;
    state.currentPreviewIdentity = null;
    state.currentEditorPath = null;
    state.currentEditorSourceID = null;
    trimModelCache();
  }

  function modelUri(path, side) {
    return window.monaco.Uri.parse(`gitn://${side}/${encodeURIComponent(state.currentSourceID)}/${encodeURIComponent(path)}`);
  }

  function trimModelCache() {
    const active = new Set(state.editors.map((editor) => editor.getModel()));
    let units = 0;
    for (const model of state.modelCache.values()) units += model.getValue().length;
    while (state.modelCache.size > 8 || units > 4_000_000) {
      const oldest = [...state.modelCache].find(([, model]) => !active.has(model));
      if (!oldest) break; // An active large file must stay readable.
      const [key, model] = oldest;
      state.modelCache.delete(key);
      units -= model.getValue().length;
      model.dispose();
    }
  }

  function disposeModelCache() {
    for (const model of state.modelCache.values()) model.dispose();
    state.modelCache.clear();
  }

  function buildDiffIdentity(item) {
    return {
      path: item && item.path ? item.path : "",
      sourceID: state.currentSourceID,
      language: item && item.language ? item.language : "",
      isEditable: !!(item && item.isEditable),
      originalText: item && typeof item.originalText === "string" ? item.originalText : "",
      modifiedText: item && typeof item.modifiedText === "string" ? item.modifiedText : "",
    };
  }

  function buildPreviewIdentity(item) {
    return {
      path: item && item.path ? item.path : "",
      sourceID: state.currentSourceID,
      language: item && item.language ? item.language : "",
      isEditable: !!(item && item.isEditable),
      content: item && typeof item.content === "string" ? item.content : "",
    };
  }

  function sameIdentity(a, b) {
    return !!a && !!b && a.path === b.path && a.sourceID === b.sourceID &&
      a.language === b.language &&
      a.isEditable === b.isEditable && a.originalText === b.originalText &&
      a.modifiedText === b.modifiedText && a.content === b.content;
  }

  function createModel(text, language, path, side) {
    const uri = modelUri(path, side);
    const key = uri.toString();
    let model = state.modelCache.get(key);
    if (!model) {
      model = window.monaco.editor.getModel(uri) ||
        window.monaco.editor.createModel(text, resolveLanguage(language, path), uri);
    } else if (model.getValue() !== text) {
      model.setValue(text); // A changed snapshot must not retain obsolete undo history.
    }
    if (typeof window.monaco.editor.setModelLanguage === "function") {
      window.monaco.editor.setModelLanguage(model, resolveLanguage(language, path));
    }
    state.modelCache.delete(key);
    state.modelCache.set(key, model);
    return model;
  }

  function resolveLanguage(language, path) {
    const normalizedLanguage = typeof language === "string" ? language.toLowerCase() : "";
    if (normalizedLanguage === "shellscript") {
      return "shell";
    }

    const normalizedPath = typeof path === "string" ? path.toLowerCase() : "";
    if (
      normalizedPath.endsWith(".sh") ||
      normalizedPath.endsWith(".bash") ||
      normalizedPath.endsWith(".zsh") ||
      normalizedPath.endsWith(".fish")
    ) {
      return "shell";
    }

    return normalizedLanguage || "plaintext";
  }

  function ensureRoot() {
    let root = document.getElementById("root");
    if (!root) {
      root = document.createElement("div");
      root.id = "root";
      document.body.appendChild(root);
    }
    return root;
  }

  function ensureTooltipElement() {
    if (state.tooltipElement && state.tooltipElement.isConnected) {
      return state.tooltipElement;
    }

    const tooltip = document.createElement("div");
    tooltip.className = "gitn-hover-tooltip";
    tooltip.hidden = true;
    document.body.appendChild(tooltip);
    state.tooltipElement = tooltip;
    return tooltip;
  }

  function hideTooltip() {
    state.activeTooltipKey = null;
    if (state.tooltipElement) {
      state.tooltipElement.hidden = true;
      state.tooltipElement.textContent = "";
    }
  }

  function showTooltip(text, event, key) {
    if (!text || !event) {
      hideTooltip();
      return;
    }

    const tooltip = ensureTooltipElement();
    if (state.activeTooltipKey !== key || tooltip.textContent !== text) {
      tooltip.textContent = text;
      state.activeTooltipKey = key;
    }

    tooltip.hidden = false;

    const offsetX = 14;
    const offsetY = 14;
    const rect = tooltip.getBoundingClientRect();
    const maxLeft = Math.max(window.innerWidth - rect.width - 8, 8);
    const maxTop = Math.max(window.innerHeight - rect.height - 8, 8);
    const left = Math.min(event.clientX + offsetX, maxLeft);
    const top = Math.min(event.clientY + offsetY, maxTop);
    tooltip.style.left = `${left}px`;
    tooltip.style.top = `${top}px`;
  }

  function bindHoverTooltip(element, text, key) {
    if (!element || !text) {
      return;
    }

    element.addEventListener("mouseenter", (event) => {
      showTooltip(text, event, key);
    });
    element.addEventListener("mousemove", (event) => {
      showTooltip(text, event, key);
    });
    element.addEventListener("mouseleave", () => {
      if (state.activeTooltipKey === key) {
        hideTooltip();
      }
    });
  }

  function resetRoot(mode) {
    reportDebug("resetRoot", {
      mode,
      currentMode: state.currentMode,
      currentEditorPath: state.currentEditorPath,
    });
    capturePendingViewState();
    disposeAllEditors();
    hideTooltip();
    const root = ensureRoot();
    if (mode === "diff") {
      root.className = "root single-diff-root";
    } else {
      root.className = "root";
    }
    root.innerHTML = "";
    state.currentMode = mode;
    return root;
  }

  function capturePendingViewState() {
    const editor = state.diffEditor || (state.editors.length > 0 ? state.editors[0] : null);
    if (!editor || typeof editor.saveViewState !== "function") {
      state.pendingViewState = null;
      return;
    }

    state.pendingViewState = {
      mode: state.currentMode,
      path: state.currentEditorPath,
      sourceID: state.currentEditorSourceID,
      viewState: editor.saveViewState(),
      scrollTop: typeof editor.getScrollTop === "function" ? editor.getScrollTop() : 0,
      scrollLeft: typeof editor.getScrollLeft === "function" ? editor.getScrollLeft() : 0,
    };
    if (state.currentEditorPath) {
      const key = state.currentMode + ":" + state.currentEditorSourceID + ":" + state.currentEditorPath;
      state.viewStates.delete(key);
      state.viewStates.set(key, state.pendingViewState);
      if (state.viewStates.size > 8) state.viewStates.delete(state.viewStates.keys().next().value);
    }
  }

  function restorePendingViewState(editor, mode, path) {
    const pending = state.viewStates.get(mode + ":" + state.currentSourceID + ":" + path) || state.pendingViewState;
    state.pendingViewState = null;

    if (!pending || pending.mode !== mode || pending.path !== path ||
        pending.sourceID !== state.currentSourceID) {
      return false;
    }

    try {
      if (pending.viewState && typeof editor.restoreViewState === "function") {
        editor.restoreViewState(pending.viewState);
      }
      if (typeof editor.setScrollPosition === "function") {
        editor.setScrollPosition({
          scrollTop: typeof pending.scrollTop === "number" ? pending.scrollTop : 0,
          scrollLeft: typeof pending.scrollLeft === "number" ? pending.scrollLeft : 0,
        });
      }
    } catch (error) {
      reportDebug("restoreViewStateFailed", {
        mode,
        path,
        message: error && error.message ? error.message : String(error),
      });
    }
    return true;
  }

  function renderPreview(payload) {
    reportDebug("renderPreview", {
      path: payload.path,
      contentLength: (payload.content || "").length,
      isEditable: !!payload.isEditable,
    });
    if (state.currentMode === "preview" && state.editors.length > 0) {
      const editor = state.editors[0];
      const previousModel = editor.getModel();
      const samePath = state.currentEditorPath === payload.path &&
        state.currentEditorSourceID === state.currentSourceID;
      if (!samePath) capturePendingViewState();
      state.isReplacingModel = true;
      let model;
      if (samePath && previousModel && typeof previousModel.setValue === "function") {
        const incomingText = payload.content || "";
        if (previousModel.getValue() !== incomingText) previousModel.setValue(incomingText);
        model = previousModel;
      } else {
        model = createModel(payload.content || "", payload.language, payload.path, "preview");
        editor.setModel(model);
      }
      state.isReplacingModel = false;
      trimModelCache();
      editor.updateOptions(editorOptions(payload.isEditable));
      state.currentPreviewLanguage = payload.language;
      state.currentPreviewEditable = !!payload.isEditable;
      state.currentPreviewIdentity = buildPreviewIdentity(payload);
      state.currentEditorPath = payload.path;
      state.currentEditorSourceID = state.currentSourceID;
      if (!samePath && !restorePendingViewState(editor, "preview", payload.path)) {
        editor.setScrollPosition({ scrollTop: 0, scrollLeft: 0 });
      }
      return;
    }
    const root = resetRoot("preview");
    const editorNode = document.createElement("div");
    editorNode.className = "preview-editor";
    root.appendChild(editorNode);

    const model = createModel(payload.content || "", payload.language, payload.path, "preview");
    const editor = window.monaco.editor.create(editorNode, Object.assign(editorOptions(payload.isEditable), {
      model,
    }));
    editor.addCommand(window.monaco.KeyMod.CtrlCmd | window.monaco.KeyCode.KeyS, () => {
      postMessage("saveRequest");
    });
    editor.onDidChangeModelContent(() => {
      if (state.isReplacingModel) return;
      state.currentPreviewIdentity = buildPreviewIdentity({
        path: state.currentEditorPath,
        language: state.currentPreviewLanguage,
        isEditable: state.currentPreviewEditable,
        content: editor.getValue(),
      });
      postMessage("contentChanged", {
        path: state.currentEditorPath,
        content: encodeBase64(editor.getValue()),
      });
    });
    state.currentPreviewLanguage = payload.language;
    state.currentPreviewEditable = !!payload.isEditable;
    state.currentPreviewIdentity = buildPreviewIdentity(payload);
    state.currentEditorPath = payload.path;
    state.currentEditorSourceID = state.currentSourceID;
    restorePendingViewState(editor, "preview", payload.path);
    state.editors.push(editor);
    trimModelCache();
  }

  function addWheelForwarding(element) {
    element.addEventListener("wheel", function(event) {
      var editor = state.diffEditor;
      if (editor) {
        editor.setScrollPosition({
          scrollTop: Math.max(0, editor.getScrollTop() + event.deltaY),
          scrollLeft: Math.max(0, editor.getScrollLeft() + event.deltaX),
        });
      }
      event.preventDefault();
      event.stopPropagation();
    }, { passive: false });
  }

  function renderNativeActions(item) {
    state.nativeItem = item;
    const bar = state.nativeActions;
    if (!bar) return;
    bar.innerHTML = "";
    state.diffModel = buildHunkControlMaps(item);
    if (state.diffDisplay === "hunk") {
      bar.hidden = true;
      renderHunkSections();
      return;
    }
    const seen = new Set();
    for (const control of state.diffModel.hunkControls) {
      if (seen.has(control.hunkIndex)) continue;
      seen.add(control.hunkIndex);
      const group = document.createElement("div");
      group.className = "gitn-native-hunk";
      const jump = document.createElement("button");
      jump.textContent = `Hunk ${control.hunkIndex + 1}`;
      jump.addEventListener("click", () => {
        const editor = control.anchorKind === "deletion"
          ? state.nativeDiff.getOriginalEditor() : state.diffEditor;
        editor.revealLineInCenter(Math.max(1, control.anchorKind === "deletion"
          ? (control.oldStartLine || control.oldLineNumber || 1)
          : (control.newStartLine || control.newLineNumber || 1)));
      });
      group.appendChild(jump);
      // These are whole Git patch hunk actions, independent of Monaco's diff indices.
      group.appendChild(createHunkActions(Object.assign({}, control, { lineIDs: [] })));
      bar.appendChild(group);
    }
    bar.hidden = seen.size === 0;
  }

  function renderHunkSections() {
    const diff = state.nativeDiff;
    if (!diff || state.diffDisplay !== "hunk") return;
    const changes = diff.getLineChanges();
    if (!changes) return;
    const original = diff.getOriginalEditor();
    const modified = diff.getModifiedEditor();
    const { buildHunkLayout, controlsForHunk, hunkHeader } = window.gitnHunkLayout;
    const layout = buildHunkLayout(changes, original.getModel().getLineCount(), modified.getModel().getLineCount());
    state.nativeLabels.textContent = layout.hunks.length === 0 ? "No changes" : `${layout.hunks.length} hunk${layout.hunks.length === 1 ? "" : "s"}`;
    state.nativeNode.hidden = layout.hunks.length === 0;
    state.nativeNode.style.visibility = "visible";
    for (const [side, editor] of [["original", original], ["modified", modified]]) {
      editor.changeViewZones(accessor => {
        for (const id of state.nativeHunkZones[side]) accessor.removeZone(id);
        state.nativeHunkZones[side] = [];
        for (const hunk of layout.hunks) {
          const header = document.createElement("div");
          header.className = side === "modified" ? "gitn-hunk-header" : "gitn-hunk-header-spacer";
          if (side === "modified") {
            const range = document.createElement("span");
            range.className = "gitn-hunk-range";
            range.textContent = hunkHeader(hunk);
            header.appendChild(range);
            const controls = controlsForHunk(hunk, state.diffModel.hunkControls);
            for (const control of controls) {
              const group = document.createElement("div");
              group.className = "gitn-hunk-header-control";
              if (controls.length > 1) {
                const label = document.createElement("span");
                label.textContent = `Git hunk ${control.hunkIndex + 1}`;
                group.appendChild(label);
              }
              group.appendChild(createHunkActions(Object.assign({}, control, { lineIDs: [] })));
              header.appendChild(group);
            }
          }
          state.nativeHunkZones[side].push(accessor.addZone({
            afterLineNumber: hunk[side].start - 1,
            heightInPx: 38,
            showInHiddenAreas: true,
            suppressMouseDown: true,
            domNode: header,
          }));
        }
      });
      if (layout.hunks.length > 0) {
        editor.setHiddenAreas(layout.hidden[side].map(range => new window.monaco.Range(range.start, 1, range.end, 1)));
      }
    }
  }

  function renderNativeDiff(item) {
    reportDebug("renderNativeDiffStart", { path: item.path, display: state.diffDisplay });
    const root = resetRoot("diff");
    const shell = document.createElement("div");
    shell.className = "gitn-native-diff";
    root.appendChild(shell);
    const labels = document.createElement("div");
    labels.className = "gitn-diff-side-labels";
    labels.textContent = state.diffDisplay === "split" ? "Original (left) · Modified (right)" : "Calculating hunks…";
    state.nativeLabels = labels;
    shell.appendChild(labels);
    const actions = document.createElement("div");
    actions.className = "gitn-native-actions";
    shell.appendChild(actions);
    state.nativeActions = actions;
    const node = document.createElement("div");
    node.className = "gitn-native-editor";
    if (state.diffDisplay === "hunk") node.style.visibility = "hidden";
    state.nativeNode = node;
    shell.appendChild(node);
    const original = createModel(item.originalText || "", item.language, item.path, "original");
    const modified = createModel(item.modifiedText || "", item.language, item.path, "modified");
    reportDebug("renderNativeDiffModelsReady");
    const diff = window.monaco.editor.createDiffEditor(node, Object.assign(editorOptions(item.isEditable), {
      renderSideBySide: state.diffDisplay === "split",
      useInlineViewWhenSpaceIsLimited: false,
      originalEditable: false,
      renderOverviewRuler: true,
      renderIndicators: true,
      diffCodeLens: false,
      maxComputationTime: 2000,
      hideUnchangedRegions: {
        enabled: false, contextLineCount: 3,
        minimumLineCount: 1, revealLineCount: 10,
      },
    }));
    state.nativeDiff = diff;
    reportDebug("renderNativeDiffEditorReady");
    diff.setModel({ original, modified });
    reportDebug("renderNativeDiffModelAssigned");
    const editor = diff.getModifiedEditor();
    state.diffEditor = editor;
    state.editors = [diff.getOriginalEditor(), editor];
    state.currentEditorPath = item.path;
    state.currentEditorSourceID = state.currentSourceID;
    state.currentDiffIdentity = buildDiffIdentity(item);
    diff.onDidUpdateDiff(() => {
      if (state.nativeDiff === diff) renderHunkSections();
    });
    renderNativeActions(item);
    reportDebug("renderNativeDiffActionsReady");
    restorePendingViewState(editor, "diff", item.path);
    editor.addCommand(window.monaco.KeyMod.CtrlCmd | window.monaco.KeyCode.KeyS, () => postMessage("saveRequest"));
    editor.onDidChangeModelContent(() => {
      const content = editor.getValue();
      state.currentDiffIdentity = buildDiffIdentity(Object.assign({}, item, { modifiedText: content }));
      renderNativeActions(Object.assign({}, item, { hunkControls: [] }));
      postMessage("contentChanged", { path: item.path, content: encodeBase64(content) });
    });
    trimModelCache();
    reportDebug("renderNativeDiffReady");
  }

  function renderSingleDiff(item) {
    try {
      if (state.currentMode === "diff" && state.diffEditor) {
        const editor = state.diffEditor;
        const previousModel = editor.getModel();
        const samePath = state.currentEditorPath === item.path &&
          state.currentEditorSourceID === state.currentSourceID;
        if (!samePath) capturePendingViewState();
        state.diffGeneration += 1;
        if (window.gitnDiffScheduler) window.gitnDiffScheduler.cancel();
        state.currentDiffOriginalText = item.originalText || "";
        state.currentDiffLanguage = item.language;
        state.currentDiffEditable = !!item.isEditable;
        state.currentEditorPath = item.path;
        state.isReplacingModel = true;
        let model;
        if (samePath && previousModel && typeof previousModel.setValue === "function") {
          const incomingText = item.modifiedText || "";
          if (previousModel.getValue() !== incomingText) previousModel.setValue(incomingText);
          model = previousModel;
        } else {
          model = createModel(item.modifiedText || "", item.language, item.path, "modified");
          editor.setModel(model);
        }
        state.isReplacingModel = false;
        trimModelCache();
        editor.updateOptions(Object.assign(editorOptions(item.isEditable), {
          lineNumbersMinChars: diffLineNumberMinChars(model.getLineCount()),
        }));
        state.currentDiffIdentity = buildDiffIdentity(item);
        state.currentEditorSourceID = state.currentSourceID;
        if (!samePath && !restorePendingViewState(editor, "diff", item.path)) {
          editor.setScrollPosition({ scrollTop: 0, scrollLeft: 0 });
        }
        renderInlineDiff(editor, item.originalText || "", editor.getValue());
        return;
      }
      const root = resetRoot("diff");
      const shellNode = document.createElement("div");
      shellNode.className = "single-diff-shell";
      root.appendChild(shellNode);

      const editorNode = document.createElement("div");
      editorNode.className = "single-diff-editor";
      shellNode.appendChild(editorNode);

      const gutterOverlay = document.createElement("div");
      gutterOverlay.className = "gitn-gutter-overlay";
      shellNode.appendChild(gutterOverlay);
      state.gutterOverlay = gutterOverlay;
      addWheelForwarding(gutterOverlay);

      const contentOverlay = document.createElement("div");
      contentOverlay.className = "gitn-content-overlay";
      shellNode.appendChild(contentOverlay);
      state.contentOverlay = contentOverlay;

      const statusNode = document.createElement("div");
      statusNode.className = "gitn-diff-status";
      statusNode.hidden = true;
      shellNode.appendChild(statusNode);
      state.diffStatus = statusNode;

      const model = createModel(item.modifiedText || "", item.language, item.path, "modified");
      const editor = window.monaco.editor.create(editorNode, Object.assign(editorOptions(item.isEditable), {
        model,
        lineDecorationsWidth: 12,
        glyphMargin: false,
        lineNumbersMinChars: diffLineNumberMinChars(model.getLineCount()),
        lineNumbers: (lineNumber) => {
          const entry = getLineNumberEntry(lineNumber);
          return entry && typeof entry.newLineNum === "number"
            ? String(entry.newLineNum)
            : String(lineNumber);
        },
      }));
      state.diffEditor = editor;
      state.currentEditorSourceID = state.currentSourceID;
      applyEditorMetrics(shellNode, editor);
      editor.addCommand(window.monaco.KeyMod.CtrlCmd | window.monaco.KeyCode.KeyS, () => {
        postMessage("saveRequest");
      });
      state.currentDiffOriginalText = item.originalText || "";
      state.currentDiffLanguage = item.language;
      state.currentDiffEditable = !!item.isEditable;
      state.currentEditorPath = item.path;
      renderInlineDiff(editor, item.originalText || "", editor.getValue());

      editor.onDidChangeModelContent(() => {
        if (state.isReplacingModel) return;
        var currentValue = editor.getValue();
        state.currentDiffIdentity = buildDiffIdentity({
          path: state.currentEditorPath,
          language: state.currentDiffLanguage,
          isEditable: state.currentDiffEditable,
          originalText: state.currentDiffOriginalText,
          modifiedText: currentValue,
        });
        renderInlineDiff(editor, state.currentDiffOriginalText, currentValue, 150);
        postMessage("contentChanged", {
          path: state.currentEditorPath,
          content: encodeBase64(currentValue),
        });
      });
      editor.onDidScrollChange(() => {
        syncCurrentHunkIndexToViewport(editor);
        scheduleDeletionGutterRender(editor);
      });
      editor.onDidLayoutChange(() => {
        applyEditorMetrics(shellNode, editor);
        scheduleDeletionGutterRender(editor);
      });
      state.currentDiffIdentity = buildDiffIdentity(item);
      restorePendingViewState(editor, "diff", item.path);
      syncCurrentHunkIndexToViewport(editor);
      state.editors.push(editor);
      trimModelCache();
    } catch (error) {
      reportError(
        `[renderSingleDiff] ${error && error.message ? error.message : String(error)}`,
        error && error.stack ? error.stack : ""
      );
    }
  }

  function applyEditorMetrics(shellNode, editor) {
    const fontInfo = editor.getOption(window.monaco.editor.EditorOption.fontInfo);
    const lineHeight = editor.getOption(window.monaco.editor.EditorOption.lineHeight);
    const layout = editor.getLayoutInfo();
    const gutterNumberOffset = Math.max(layout.contentLeft - layout.lineNumbersWidth, 0);
    const model = editor.getModel();
    const tabSize = model ? model.getOptions().tabSize : 4;
    shellNode.style.setProperty("--gitn-font-size", `${fontInfo.fontSize}px`);
    shellNode.style.setProperty("--gitn-line-height", `${lineHeight}px`);
    shellNode.style.setProperty("--gitn-font-family", fontInfo.fontFamily || "ui-monospace, SFMono-Regular, Menlo, monospace");
    shellNode.style.setProperty("--gitn-font-weight", fontInfo.fontWeight || "normal");
    shellNode.style.setProperty("--gitn-content-left", `${layout.contentLeft}px`);
    shellNode.style.setProperty("--gitn-line-numbers-width", `${layout.lineNumbersWidth}px`);
    shellNode.style.setProperty("--gitn-line-decorations-width", `${layout.lineDecorationsWidth}px`);
    shellNode.style.setProperty("--gitn-gutter-number-offset", `${gutterNumberOffset}px`);
    shellNode.style.setProperty("--gitn-deletion-number-column-width", `${layout.lineNumbersWidth}px`);
    shellNode.style.setProperty("--gitn-deletion-accent-width", "3px");
    shellNode.style.setProperty("--gitn-tab-size", String(tabSize));
  }

  function applyOverlayLayout(editor) {
    if (!state.gutterOverlay || !state.contentOverlay) {
      return null;
    }

    const layout = editor.getLayoutInfo();
    state.gutterOverlay.style.width = `${layout.contentLeft}px`;
    state.gutterOverlay.style.transform = "translate(0, 0)";
    state.contentOverlay.style.left = `${layout.contentLeft}px`;
    state.contentOverlay.style.right = "0";
    state.contentOverlay.style.transform = "translateX(0)";
    return layout;
  }

  function createGutterNumberContent(entry) {
    const content = document.createElement("div");
    content.className = "gitn-gutter-number-content";
    const blameTooltip = getLineBlameTooltip(entry);
    bindHoverTooltip(content, blameTooltip, `blame:${entry && entry.oldLineNum}:${entry && entry.newLineNum}`);

    const oldNumber = document.createElement("span");
    oldNumber.className = "gitn-gutter-old-number";
    oldNumber.textContent = formatLineNumber(entry && entry.oldLineNum);
    content.appendChild(oldNumber);

    return content;
  }

  function getLineBlameTooltip(entry) {
    if (!entry || !state.diffModel || !state.diffModel.lineBlames) {
      return "";
    }

    if (typeof entry.oldLineNum === "number" && state.diffModel.lineBlames.byOldLine.has(entry.oldLineNum)) {
      return state.diffModel.lineBlames.byOldLine.get(entry.oldLineNum) || "";
    }

    if (typeof entry.newLineNum === "number" && state.diffModel.lineBlames.byNewLine.has(entry.newLineNum)) {
      return state.diffModel.lineBlames.byNewLine.get(entry.newLineNum) || "";
    }

    return "";
  }

  function createVisibleGutterLine(entry, top) {
    const line = document.createElement("div");
    line.className = "gitn-gutter-overlay-line";
    line.style.top = `${top}px`;
    const control = getHunkControlForNewLine(entry && entry.newLineNum);
    if (control) {
      line.classList.add("gitn-gutter-overlay-line-with-actions");
      line.appendChild(createHunkActions(control));
    }
    line.appendChild(createGutterNumberContent(entry));
    return line;
  }

  function getPrimaryHunkAction() {
    return state.diffModel && typeof state.diffModel.primaryHunkAction === "string"
      ? state.diffModel.primaryHunkAction
      : null;
  }

  function showsDiscardHunkAction() {
    return !!(state.diffModel && state.diffModel.showsDiscardAction);
  }

  function getHunkControlForNewLine(lineNumber) {
    if (!state.diffModel || !Array.isArray(state.diffModel.hunkControls) || typeof lineNumber !== "number") {
      return null;
    }
    for (const control of state.diffModel.hunkControls) {
      if (control.anchorKind !== "addition") {
        continue;
      }
      if (typeof control.newLineNumber === "number" &&
          lineNumber === control.newLineNumber) {
        return control;
      }
    }
    return null;
  }

  function getHunkControlForDeletedLines(lines) {
    if (!state.diffModel || !Array.isArray(state.diffModel.hunkControls) || !Array.isArray(lines)) {
      return null;
    }
    for (const line of lines) {
      if (line && typeof line.oldLineNum === "number") {
        for (const control of state.diffModel.hunkControls) {
          if (control.anchorKind !== "deletion") {
            continue;
          }
          if (typeof control.oldLineNumber === "number" &&
              line.oldLineNum === control.oldLineNumber) {
            return control;
          }
        }
      }
    }
    return null;
  }

  function postHunkAction(control, action) {
    if (!control || !action) {
      return;
    }
    postMessage("hunkAction", {
      path: control.path,
      action,
      hunkIndex: control.hunkIndex,
      lineIDs: Array.isArray(control.lineIDs) ? control.lineIDs : [],
    });
  }

  function createHunkActionButton(action, label, title, control) {
    const button = document.createElement("button");
    button.className = `gitn-hunk-action gitn-hunk-action-${action}`;
    button.type = "button";
    button.textContent = label;
    button.title = title;
    button.setAttribute("aria-label", title);
    button.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      postHunkAction(control, action);
    });
    return button;
  }

  function createHunkActions(control) {
    const actions = document.createElement("div");
    actions.className = "gitn-hunk-actions";

    if (showsDiscardHunkAction()) {
      const discardTitle = control.tooltip
        ? `放弃区块 (${control.tooltip})`
        : "放弃区块";
      actions.appendChild(createHunkActionButton("discard", "↶", discardTitle, control));
    }

    const primaryAction = getPrimaryHunkAction();
    if (primaryAction === "stage" || primaryAction === "unstage") {
      const primaryTitle = primaryAction === "stage"
        ? (control.tooltip ? `暂存区块 (${control.tooltip})` : "暂存区块")
        : (control.tooltip ? `移除暂存 (${control.tooltip})` : "移除暂存");
      const primaryLabel = primaryAction === "stage" ? "+" : "−";
      actions.appendChild(createHunkActionButton(primaryAction, primaryLabel, primaryTitle, control));
    }

    return actions;
  }

  function resolveZoneMeasurementNode(entry) {
    if (!entry || !entry.spacerNode || !entry.spacerNode.isConnected) {
      return null;
    }

    if (typeof entry.spacerNode.closest === "function") {
      const zoneNode = entry.spacerNode.closest(".view-zone");
      if (zoneNode) {
        return zoneNode;
      }
    }

    const parent = entry.spacerNode.parentElement;
    if (parent && parent.classList && parent.classList.contains("view-zone")) {
      return parent;
    }

    return entry.spacerNode;
  }

  function resolveDeletionBlockFrame(editor, gutterOverlay, entry) {
    const fallbackHeight = entry.heightInLines * editor.getOption(window.monaco.editor.EditorOption.lineHeight);
    const fallbackTop = deletionBlockTop(editor, entry.anchorLine, fallbackHeight);

    if (!entry || !entry.spacerNode || !entry.spacerNode.isConnected) {
      return { top: fallbackTop, height: fallbackHeight };
    }

    const scrollTop = editor.getScrollTop();
    const measurementNode = resolveZoneMeasurementNode(entry);

    const spacerTop = measurementNode && typeof measurementNode.offsetTop === "number"
      ? measurementNode.offsetTop
      : null;
    const spacerHeight = measurementNode && typeof measurementNode.offsetHeight === "number"
      ? measurementNode.offsetHeight
      : null;

    if (spacerTop === null || spacerHeight === null || spacerHeight <= 0) {
      return { top: fallbackTop, height: fallbackHeight };
    }

    return {
      top: spacerTop - scrollTop,
      height: spacerHeight,
    };
  }

  function visibleDeletionFrames(editor, gutterOverlay, renderDeletions) {
    const viewportTop = 0;
    const layout = editor.getLayoutInfo();
    const viewportHeight = layout ? layout.height : 0;
    const viewportBottom = viewportTop + viewportHeight;
    const overscan = Math.max(viewportHeight, 600);

    return Array.isArray(renderDeletions)
      ? renderDeletions.map((entry) => {
          const frame = resolveDeletionBlockFrame(editor, gutterOverlay, entry);
          return {
            entry,
            frame,
            isVisible: frame.top < (viewportBottom + overscan) && (frame.top + frame.height) > (viewportTop - overscan),
          };
        })
      : [];
  }

  function renderVisibleGutter(editor, gutterOverlay, deletionFrames) {
    const visibleRanges = editor.getVisibleRanges();
    const scrollTop = editor.getScrollTop();
    const seenLines = new Set();
    const lineHeight = editor.getOption(window.monaco.editor.EditorOption.lineHeight);
    const hiddenRanges = Array.isArray(deletionFrames)
      ? deletionFrames.filter((item) => item.isVisible).map((item) => ({
          top: item.frame.top,
          bottom: item.frame.top + item.frame.height,
        }))
      : [];

    for (const range of visibleRanges) {
      for (let lineNumber = range.startLineNumber; lineNumber <= range.endLineNumber; lineNumber += 1) {
        if (seenLines.has(lineNumber)) {
          continue;
        }
        seenLines.add(lineNumber);

        const entry = getLineNumberEntry(lineNumber) || {
          oldLineNum: null,
          newLineNum: lineNumber,
        };
        const top = editor.getTopForLineNumber(lineNumber) - scrollTop;
        const bottom = top + lineHeight;
        const overlapsDeletion = hiddenRanges.some((hiddenRange) => (
          bottom > hiddenRange.top && top < hiddenRange.bottom
        ));
        if (overlapsDeletion) {
          continue;
        }
        gutterOverlay.appendChild(createVisibleGutterLine(entry, top));
      }
    }
  }

  function deletionBlockTop(editor, anchorLine, zoneHeight) {
    const scrollTop = editor.getScrollTop();
    const modelLineCount = editor.getModel().getLineCount();
    if (anchorLine > modelLineCount) {
      return editor.getScrollHeight() - scrollTop - zoneHeight;
    }
    if (anchorLine <= 1) {
      return -scrollTop;
    }
    return editor.getTopForLineNumber(anchorLine) - scrollTop - zoneHeight;
  }

  function visibleDeletionLineRange(top, zoneHeight, lineHeight, viewportHeight) {
    const overscanLines = 12;
    const visibleTop = Math.max(0, -top);
    const visibleBottom = Math.min(zoneHeight, viewportHeight - top);
    const start = Math.max(0, Math.floor(visibleTop / lineHeight) - overscanLines);
    const end = Math.max(
      start,
      Math.min(
        Math.ceil(visibleBottom / lineHeight) + overscanLines,
        Math.ceil(zoneHeight / lineHeight)
      )
    );
    return { start, end };
  }

  function createDeletionGutterBlock(entry, top, zoneHeight, lineHeight, viewportHeight) {
    const gutterBlock = document.createElement("div");
    gutterBlock.className = "gitn-deletion-gutter-block";
    gutterBlock.style.top = `${top}px`;
    gutterBlock.style.height = `${zoneHeight}px`;
    if (entry.hasAddition) {
      gutterBlock.classList.add("gitn-deletion-gutter-block-with-addition");
    }

    const control = getHunkControlForDeletedLines(entry.deletedLines);
    if (control) {
      gutterBlock.classList.add("gitn-deletion-gutter-block-with-actions");
      gutterBlock.appendChild(createHunkActions(control));
    }

    const range = visibleDeletionLineRange(top, zoneHeight, lineHeight, viewportHeight);
    const rowsContainer = document.createElement("div");
    rowsContainer.style.transform = `translateY(${range.start * lineHeight}px)`;

    for (const line of entry.deletedLines.slice(range.start, range.end)) {
      const row = document.createElement("div");
      row.className = "gitn-deletion-gutter-line";
      row.appendChild(createGutterNumberContent({
        oldLineNum: line.oldLineNum,
        newLineNum: null,
      }));

      rowsContainer.appendChild(row);
    }

    gutterBlock.appendChild(rowsContainer);

    return gutterBlock;
  }

  function createDeletionContentBlock(entry, top, zoneHeight, scrollLeft, lineHeight, viewportHeight) {
    const contentBlock = document.createElement("div");
    contentBlock.className = "gitn-deletion-content-block";
    contentBlock.style.top = `${top}px`;
    contentBlock.style.height = `${zoneHeight}px`;
    addWheelForwarding(contentBlock);

    const scrollContent = document.createElement("div");
    scrollContent.className = "gitn-deletion-content-scroll";
    scrollContent.style.transform = `translateX(${-scrollLeft}px)`;

    const range = visibleDeletionLineRange(top, zoneHeight, lineHeight, viewportHeight);
    const rowsContainer = document.createElement("div");
    rowsContainer.style.transform = `translateY(${range.start * lineHeight}px)`;

    for (const line of entry.deletedLines.slice(range.start, range.end)) {
      const row = document.createElement("div");
      row.className = "gitn-deletion-line";

      const content = document.createElement("span");
      content.className = "gitn-deletion-line-content";

      const text = line.content || "";
      const hl = line.inlineHighlight;
      // Render inline character highlight when a paired addition exists.
      // Column values are 1-based UTF-16, so convert to 0-based JS string indices.
      if (hl && hl.startColumn < hl.endColumn && hl.endColumn - 1 <= text.length) {
        const start = hl.startColumn - 1;
        const end = hl.endColumn - 1;
        if (start > 0) {
          content.appendChild(document.createTextNode(text.slice(0, start)));
        }
        const hlSpan = document.createElement("span");
        hlSpan.className = "gitn-inline-deletion";
        hlSpan.textContent = text.slice(start, end);
        content.appendChild(hlSpan);
        if (end < text.length) {
          content.appendChild(document.createTextNode(text.slice(end)));
        }
      } else {
        content.textContent = text;
      }

      row.appendChild(content);
      rowsContainer.appendChild(row);
    }

    scrollContent.appendChild(rowsContainer);
    contentBlock.appendChild(scrollContent);
    return contentBlock;
  }

  function isEditorAlive(editor) {
    return !!(editor && typeof editor.getScrollTop === "function" && typeof editor.getModel === "function");
  }

  function scheduleDeletionGutterRender(editor) {
    if (!isEditorAlive(editor)) {
      return;
    }
    if (state.pendingGutterAnimationFrame !== null) {
      return;
    }
    state.pendingGutterAnimationFrame = window.requestAnimationFrame(() => {
      state.pendingGutterAnimationFrame = null;
      if (isEditorAlive(editor)) {
        renderDeletionGutter(editor);
      }
    });
  }

  function installDeletionZoneObservers(editor, renderDeletions) {
    if (state.zoneResizeObserver) {
      try {
        state.zoneResizeObserver.disconnect();
      } catch (_) {}
      state.zoneResizeObserver = null;
    }

    if (typeof window.ResizeObserver !== "function") {
      scheduleDeletionGutterRender(editor);
      return;
    }

    const observer = new window.ResizeObserver(() => {
      scheduleDeletionGutterRender(editor);
    });

    for (const entry of renderDeletions) {
      const measurementNode = resolveZoneMeasurementNode(entry);
      if (measurementNode) {
        try {
          observer.observe(measurementNode);
        } catch (_) {}
      }
    }

    state.zoneResizeObserver = observer;
    scheduleDeletionGutterRender(editor);
  }

  function clearInlineDiff(editor) {
    if (state.diffDecorations.length > 0) {
      state.diffDecorations = editor.deltaDecorations(state.diffDecorations, []);
    }
    if (state.diffZoneIds.length > 0) {
      editor.changeViewZones((accessor) => {
        for (const zoneId of state.diffZoneIds) {
          accessor.removeZone(zoneId);
        }
      });
      state.diffZoneIds = [];
    }
    if (state.gutterOverlay) {
      state.gutterOverlay.innerHTML = "";
    }
    if (state.contentOverlay) {
      state.contentOverlay.innerHTML = "";
    }
    state.diffModel = null;
    state.currentHunkIndex = -1;
  }

  function buildHunkControlMaps(item) {
    const controls = Array.isArray(item.hunkControls) ? item.hunkControls : [];
    const normalizedControls = controls.map((control) => ({
      path: item.path,
      row: control.row,
      hunkIndex: control.hunkIndex,
      lineIDs: Array.isArray(control.lineIDs) ? control.lineIDs : [],
      tooltip: control.tooltip || "",
      anchorKind: control.anchorKind === "deletion" ? "deletion" : "addition",
      oldLineNumber: typeof control.oldLineNumber === "number" ? control.oldLineNumber : null,
      newLineNumber: typeof control.newLineNumber === "number" ? control.newLineNumber : null,
      oldStartLine: typeof control.oldStartLine === "number" ? control.oldStartLine : null,
      oldEndLine: typeof control.oldEndLine === "number" ? control.oldEndLine : null,
      newStartLine: typeof control.newStartLine === "number" ? control.newStartLine : null,
      newEndLine: typeof control.newEndLine === "number" ? control.newEndLine : null,
      hasDeletionLines: !!control.hasDeletionLines,
    }));

    return {
      primaryHunkAction: typeof item.primaryHunkAction === "string" ? item.primaryHunkAction : null,
      showsDiscardAction: !!item.showsDiscardAction,
      hunkControls: normalizedControls,
    };
  }

  function buildLineBlameMaps(item) {
    const lineBlames = Array.isArray(item.lineBlames) ? item.lineBlames : [];
    const byOldLine = new Map();
    const byNewLine = new Map();

    for (const blame of lineBlames) {
      const tooltip = typeof blame.tooltip === "string" ? blame.tooltip : "";
      if (!tooltip) {
        continue;
      }
      if (typeof blame.oldLineNumber === "number" && !byOldLine.has(blame.oldLineNumber)) {
        byOldLine.set(blame.oldLineNumber, tooltip);
      }
      if (typeof blame.newLineNumber === "number" && !byNewLine.has(blame.newLineNumber)) {
        byNewLine.set(blame.newLineNumber, tooltip);
      }
    }

    return {
      byOldLine,
      byNewLine,
    };
  }

  function buildMonacoDecorations(diffModel) {
    const decorations = [];

    for (const addition of diffModel.additionDecorations) {
      if (addition.startLineNumber > 0 && addition.endLineNumber >= addition.startLineNumber) {
        decorations.push({
          range: new window.monaco.Range(addition.startLineNumber, 1, addition.endLineNumber, 1),
          options: {
            isWholeLine: true,
            className: "gitn-line-addition",
            overviewRuler: {
              color: "rgba(46, 160, 67, 0.95)",
              position: window.monaco.editor.OverviewRulerLane.Left,
            },
          },
        });
      }
    }

    // Inline character-level highlights for changed sub-ranges within addition lines.
    // Mirrors Swift's buildInlineHighlights logic (RepoViewModel) — only paired
    // addition lines (those that replaced a deletion) get an inline highlight.
    if (diffModel.additionInlineHighlights) {
      for (const [lineNumber, highlight] of diffModel.additionInlineHighlights) {
        if (highlight && highlight.startColumn < highlight.endColumn) {
          decorations.push({
            range: new window.monaco.Range(
              lineNumber, highlight.startColumn,
              lineNumber, highlight.endColumn
            ),
            options: {
              inlineClassName: "gitn-inline-addition",
            },
          });
        }
      }
    }

    return decorations;
  }

  function buildRenderDeletions(editor, diffModel) {
    const renderDeletions = [];
    const deletionZones = [];
    const modelLineCount = editor.getModel().getLineCount();

    for (const entry of diffModel.deletionEntries) {
      const anchorLine = entry.modifiedStartLineNumber > 0
        ? entry.modifiedStartLineNumber
        : Math.min(
            modelLineCount + 1,
            Math.max(entry.anchorModifiedLineNumber || 1, 1)
          );
      if (entry.deletedLines.length === 0) {
        continue;
      }

      const spacerNode = createDeletionSpacer(renderDeletions.length);
      deletionZones.push({
        afterLineNumber: Math.max(anchorLine - 1, 0),
        heightInLines: entry.deletedLines.length,
        domNode: spacerNode,
      });
      renderDeletions.push({
        id: `deletion-${renderDeletions.length}`,
        zoneIndex: renderDeletions.length,
        anchorLine: Math.max(anchorLine, 1),
        heightInLines: entry.deletedLines.length,
        deletedLines: entry.deletedLines,
        hasAddition: entry.hasAddition,
        spacerNode,
      });
    }

    return {
      deletionZones,
      renderDeletions,
    };
  }

  function renderInlineDiff(editor, originalText, modifiedText, delay = 0) {
    const generation = ++state.diffGeneration;
    if (window.gitnDiffScheduler) window.gitnDiffScheduler.cancel();
    if (state.diffTimer !== null) clearTimeout(state.diffTimer);
    clearInlineDiff(editor);
    if (state.diffStatus) {
      state.diffStatus.textContent = "Computing diff…";
      state.diffStatus.hidden = false;
    }
    const isCurrent = () => state.diffGeneration === generation &&
      state.diffEditor === editor &&
      state.currentDiffOriginalText === originalText &&
      editor.getValue() === modifiedText;

    // Let Monaco paint the file text before launching potentially expensive diff work.
    state.diffTimer = setTimeout(() => {
      state.diffTimer = null;
      if (!isCurrent()) return;
      if (!window.gitnDiffScheduler) {
        if (state.diffStatus) state.diffStatus.textContent = "Diff worker unavailable. Text remains available.";
        return;
      }
      window.gitnDiffScheduler.run(originalText, modifiedText).then((diffModel) => {
        if (!isCurrent() || !diffModel) return;
        try {
          applyInlineDiffModel(editor, diffModel);
          if (state.diffStatus) state.diffStatus.hidden = true;
        } catch (error) {
          reportError("Failed to render diff", error && error.stack ? error.stack : String(error));
          if (state.diffStatus) state.diffStatus.textContent = "Diff rendering failed. Text remains available.";
        }
      }).catch((error) => {
        if (!isCurrent()) return;
        if (state.diffStatus) state.diffStatus.textContent = error.message || String(error);
        reportError("Failed to compute diff", error && error.stack ? error.stack : String(error));
      });
    }, delay);
  }

  function applyInlineDiffModel(editor, diffModel) {
    try {
      const lastRow = diffModel.rows[diffModel.rows.length - 1];
      const maxLine = Math.max(editor.getModel().getLineCount(),
        lastRow && lastRow.oldLineNum || 0, lastRow && lastRow.newLineNum || 0);
      const minChars = diffLineNumberMinChars(maxLine);
      if (editor.getOption(window.monaco.editor.EditorOption.lineNumbersMinChars) !== minChars) {
        editor.updateOptions({ lineNumbersMinChars: minChars });
      }
      const decorations = buildMonacoDecorations(diffModel);
      const { deletionZones, renderDeletions } = buildRenderDeletions(editor, diffModel);

      for (const entry of renderDeletions) {
        decorations.push({
          range: new window.monaco.Range(Math.max(entry.anchorLine, 1), 1, Math.max(entry.anchorLine, 1), 1),
          options: {
            isWholeLine: false,
            overviewRuler: {
              color: "rgba(248, 81, 73, 0.95)",
              position: window.monaco.editor.OverviewRulerLane.Right,
            },
          },
        });
      }

      state.diffDecorations = editor.deltaDecorations([], decorations);
      editor.changeViewZones((accessor) => {
        for (const zone of deletionZones) {
          const zoneId = accessor.addZone(zone);
          state.diffZoneIds.push(zoneId);
        }
      });
      state.diffModel = Object.assign({}, diffModel, buildHunkControlMaps({
        path: state.pendingHunkActions && state.pendingHunkActions.path,
        primaryHunkAction: state.pendingHunkActions && state.pendingHunkActions.primaryHunkAction,
        showsDiscardAction: state.pendingHunkActions && state.pendingHunkActions.showsDiscardAction,
        hunkControls: state.pendingHunkActions && state.pendingHunkActions.hunkControls,
      }), {
        lineBlames: buildLineBlameMaps({
          lineBlames: state.pendingLineBlames,
        }),
        renderDeletions,
      });
      renderDeletionGutter(editor);
      installDeletionZoneObservers(editor, renderDeletions);
    } catch (error) {
      reportError(
        `[renderInlineDiff] ${error && error.message ? error.message : String(error)}`,
        error && error.stack ? error.stack : ""
      );
    }
  }

  function createDeletionSpacer(zoneIndex) {
    const container = document.createElement("div");
    container.className = "gitn-deletion-spacer";
    container.dataset.zoneIndex = String(zoneIndex);
    return container;
  }

  function renderDeletionGutter(editor) {
    if (!state.gutterOverlay || !state.contentOverlay || !state.diffModel) {
      return;
    }

    const gutterOverlay = state.gutterOverlay;
    const contentOverlay = state.contentOverlay;
    gutterOverlay.innerHTML = "";
    contentOverlay.innerHTML = "";

    const lineHeight = editor.getOption(window.monaco.editor.EditorOption.lineHeight);
    applyOverlayLayout(editor);
    const scrollLeft = editor.getScrollLeft();
    const layout = editor.getLayoutInfo();
    const viewportHeight = layout ? layout.height : 0;
    const renderDeletions = Array.isArray(state.diffModel.renderDeletions) ? state.diffModel.renderDeletions : [];
    const deletionFrames = visibleDeletionFrames(editor, gutterOverlay, renderDeletions);
    renderVisibleGutter(editor, gutterOverlay, deletionFrames);

    for (const item of deletionFrames) {
      if (!item.isVisible) {
        continue;
      }
      const entry = item.entry;
      const zoneHeight = item.frame.height;
      const top = item.frame.top;
      gutterOverlay.appendChild(createDeletionGutterBlock(entry, top, zoneHeight, lineHeight, viewportHeight));
      contentOverlay.appendChild(createDeletionContentBlock(entry, top, zoneHeight, scrollLeft, lineHeight, viewportHeight));
    }
  }

  function updateDiffMetadata(item) {
    if (!state.diffEditor) {
      return false;
    }

    if (!state.diffModel) return true;

    state.diffModel = Object.assign({}, state.diffModel, buildHunkControlMaps({
      path: item.path,
      primaryHunkAction: item.primaryHunkAction || null,
      showsDiscardAction: !!item.showsDiscardAction,
      hunkControls: Array.isArray(item.hunkControls) ? item.hunkControls : [],
    }), {
      lineBlames: buildLineBlameMaps({
        lineBlames: Array.isArray(item.lineBlames) ? item.lineBlames : [],
      }),
    });
    renderDeletionGutter(state.diffEditor);
    syncCurrentHunkIndexToViewport(state.diffEditor);
    return true;
  }

  function applyTheme(isDark) {
    document.body.classList.toggle("theme-dark", !!isDark);
    document.body.classList.toggle("theme-light", !isDark);
    window.monaco.editor.setTheme(isDark ? "vs-dark" : "vs");
  }

  function ensureMonacoReady() {
    return !!(window.monaco && window.monaco.editor);
  }

  function getDiffHunkLines() {
    if (!state.diffModel) {
      return [];
    }
    const lines = [];
    for (const add of (state.diffModel.additionDecorations || [])) {
      if (typeof add.startLineNumber === "number") {
        lines.push(add.startLineNumber);
      }
    }
    for (const del of (state.diffModel.renderDeletions || [])) {
      if (typeof del.anchorLine === "number") {
        lines.push(Math.max(del.anchorLine - 1, 1));
      }
    }
    const unique = Array.from(new Set(lines)).sort(function(a, b) { return a - b; });
    return unique;
  }

  function syncCurrentHunkIndexToViewport(editor) {
    if (!editor || !state.diffModel) {
      state.currentHunkIndex = -1;
      return;
    }

    var hunkLines = getDiffHunkLines();
    if (hunkLines.length === 0) {
      state.currentHunkIndex = -1;
      return;
    }

    var layoutInfo = editor.getLayoutInfo();
    var viewportAnchor = editor.getScrollTop() + (layoutInfo ? layoutInfo.height / 2 : 0);
    var bestIndex = 0;
    var bestDistance = Number.POSITIVE_INFINITY;

    for (var i = 0; i < hunkLines.length; i += 1) {
      var distance = Math.abs(editor.getTopForLineNumber(hunkLines[i]) - viewportAnchor);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }

    state.currentHunkIndex = bestIndex;
  }

  function navigateDiff(direction) {
    if (!state.diffEditor || !state.diffModel) {
      return;
    }
    var editor = state.diffEditor;
    var hunkLines = getDiffHunkLines();
    if (hunkLines.length === 0) {
      return;
    }

    syncCurrentHunkIndexToViewport(editor);
    var idx = state.currentHunkIndex;

    if (idx < 0 || idx >= hunkLines.length) {
      // Index not yet set: seed from current scroll position.
      // scrollTop / lineHeight is an approximation but good enough for the
      // initial seed — subsequent clicks use the reliable ±1 index path.
      var lineHeight = editor.getOption(window.monaco.editor.EditorOption.lineHeight);
      var topLine = Math.floor(editor.getScrollTop() / lineHeight) + 1;
      if (direction === "next") {
        idx = 0;
        for (var i = 0; i < hunkLines.length; i++) {
          if (hunkLines[i] > topLine) { idx = i; break; }
        }
      } else {
        idx = hunkLines.length - 1;
        for (var j = hunkLines.length - 1; j >= 0; j--) {
          if (hunkLines[j] < topLine) { idx = j; break; }
        }
      }
    } else {
      if (direction === "next") {
        idx = (idx + 1) % hunkLines.length;
      } else {
        idx = (idx - 1 + hunkLines.length) % hunkLines.length;
      }
    }

    state.currentHunkIndex = idx;
    editor.revealLineInCenter(hunkLines[idx]);
  }

  window.gitnMonaco = {
    loadPayload(encodedPayload) {
      try {
        if (!ensureMonacoReady()) {
          throw new Error("Monaco editor runtime is not ready");
        }
        const payload = JSON.parse(decodeBase64(encodedPayload));
        state.currentSourceID = typeof payload.sourceID === "string" ? payload.sourceID : "";
        applyTheme(payload.isDark);
        if (payload.mode === "conflict" && payload.conflict) {
          if (state.currentMode !== "conflict") { disposeAllEditors(); state.currentMode = "conflict"; }
          window.gitnConflict.load(payload.conflict, state.currentSourceID);
          return;
        }
        if (state.currentMode === "conflict") { window.gitnConflict.dispose(); state.currentMode = null; }
        if (payload.mode === "preview" && payload.preview) {
          reportDebug("loadPayloadPreview", {
            path: payload.preview.path,
            contentLength: (payload.preview.content || "").length,
            currentMode: state.currentMode,
            hasCurrentPreview: !!state.currentPreviewIdentity,
          });
          state.pendingHunkActions = null;
          state.pendingLineBlames = null;
          const nextIdentity = buildPreviewIdentity(payload.preview);
          if (state.currentMode === "preview" &&
              sameIdentity(state.currentPreviewIdentity, nextIdentity)) {
            reportDebug("loadPayloadPreviewSkippedSameIdentity", {
              path: payload.preview.path,
            });
            return;
          }
          renderPreview(payload.preview);
          return;
        }
        if (payload.mode === "diff" && payload.items && payload.items.length > 0) {
          const display = payload.diffDisplay === "split" || payload.diffDisplay === "hunk"
            ? payload.diffDisplay : "inline";
          if (display !== state.diffDisplay) {
            resetRoot("diff");
            state.diffDisplay = display;
          }
          const item = payload.items[0];
          if (display !== "inline") {
            if (state.nativeDiff && sameIdentity(state.currentDiffIdentity, buildDiffIdentity(item))) {
              renderNativeActions(item);
            } else {
              renderNativeDiff(item);
            }
            return;
          }
          // A preview/conflict transition may have disposed the native editor already.
          state.pendingHunkActions = {
            path: item.path,
            primaryHunkAction: item.primaryHunkAction || null,
            showsDiscardAction: !!item.showsDiscardAction,
            hunkControls: Array.isArray(item.hunkControls) ? item.hunkControls : [],
          };
          state.pendingLineBlames = Array.isArray(item.lineBlames) ? item.lineBlames : [];

          const nextIdentity = buildDiffIdentity(item);
          if (state.currentMode === "diff" &&
              sameIdentity(state.currentDiffIdentity, nextIdentity) &&
              updateDiffMetadata(item)) {
            return;
          }

          renderSingleDiff(item);
          return;
        }
      } catch (error) {
        reportError(error && error.message ? error.message : error, error && error.stack ? error.stack : "");
      }
    },
    navigateDiff(direction) {
      if (state.nativeDiff) {
        state.nativeDiff.goToDiff(direction === "next" ? "next" : "previous");
        return;
      }
      navigateDiff(direction);
    },
  };

  document.addEventListener("DOMContentLoaded", () => {
    ensureRoot();
    state.isReady = true;
    postMessage("ready");
  });

  window.addEventListener("error", (event) => {
    reportError(event.message || "Window error", event.error && event.error.stack ? event.error.stack : "");
  });
  window.addEventListener("pagehide", disposeModelCache);
})();
