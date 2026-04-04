(function () {
  const state = {
    editors: [],
    currentMode: null,
    isReady: false,
    diffEditor: null,
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
    pendingViewState: null,
    pendingGutterAnimationFrame: null,
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
    state.currentDiffIdentity = null;
    state.currentPreviewIdentity = null;
    state.currentEditorPath = null;

    const models = window.monaco && window.monaco.editor ? window.monaco.editor.getModels() : [];
    for (const model of models) {
      try {
        if (model.uri && model.uri.scheme === "gitn") {
          model.dispose();
        }
      } catch (_) {}
    }
  }

  function modelUri(path, side) {
    return window.monaco.Uri.parse(`gitn://${side}/${encodeURIComponent(path)}`);
  }

  function buildDiffIdentity(item) {
    return JSON.stringify({
      path: item && item.path ? item.path : "",
      language: item && item.language ? item.language : "",
      isEditable: !!(item && item.isEditable),
      originalText: item && typeof item.originalText === "string" ? item.originalText : "",
      modifiedText: item && typeof item.modifiedText === "string" ? item.modifiedText : "",
    });
  }

  function buildPreviewIdentity(item) {
    return JSON.stringify({
      path: item && item.path ? item.path : "",
      language: item && item.language ? item.language : "",
      isEditable: !!(item && item.isEditable),
      content: item && typeof item.content === "string" ? item.content : "",
    });
  }

  function createModel(text, language, path, side) {
    const uri = modelUri(path, side);
    const existingModel = window.monaco.editor.getModel(uri);
    if (existingModel) {
      existingModel.dispose();
    }
    return window.monaco.editor.createModel(text, language || "plaintext", uri);
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
      viewState: editor.saveViewState(),
      scrollTop: typeof editor.getScrollTop === "function" ? editor.getScrollTop() : 0,
      scrollLeft: typeof editor.getScrollLeft === "function" ? editor.getScrollLeft() : 0,
    };
  }

  function restorePendingViewState(editor, mode, path) {
    const pending = state.pendingViewState;
    state.pendingViewState = null;

    if (!pending || pending.mode !== mode || pending.path !== path) {
      return;
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
  }

  function renderPreview(payload) {
    reportDebug("renderPreview", {
      path: payload.path,
      contentLength: (payload.content || "").length,
      isEditable: !!payload.isEditable,
    });
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
      state.currentPreviewIdentity = buildPreviewIdentity({
        path: payload.path,
        language: payload.language,
        isEditable: payload.isEditable,
        content: editor.getValue(),
      });
      postMessage("contentChanged", {
        path: payload.path,
        content: encodeBase64(editor.getValue()),
      });
    });
    state.currentPreviewIdentity = buildPreviewIdentity(payload);
    state.currentEditorPath = payload.path;
    restorePendingViewState(editor, "preview", payload.path);
    state.editors.push(editor);
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

  function renderSingleDiff(item) {
    try {
      console.log("[MonacoHost] render diff", {
        path: item.path,
        originalLines: (item.originalText || "").split("\n").length,
        modifiedLines: (item.modifiedText || "").split("\n").length,
        originalBytes: (item.originalText || "").length,
        modifiedBytes: (item.modifiedText || "").length,
      });
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

      const originalModel = createModel(item.originalText || "", item.language, item.path, "original");
      const model = createModel(item.modifiedText || "", item.language, item.path, "modified");
      const editor = window.monaco.editor.create(editorNode, Object.assign(editorOptions(item.isEditable), {
        model,
        lineDecorationsWidth: 12,
        glyphMargin: false,
        lineNumbersMinChars: 10,
        lineNumbers: (lineNumber) => {
          const entry = getLineNumberEntry(lineNumber);
          return entry && typeof entry.newLineNum === "number"
            ? String(entry.newLineNum)
            : String(lineNumber);
        },
      }));
      state.diffEditor = editor;
      applyEditorMetrics(shellNode, editor);
      editor.addCommand(window.monaco.KeyMod.CtrlCmd | window.monaco.KeyCode.KeyS, () => {
        postMessage("saveRequest");
      });
      renderInlineDiff(editor, item.originalText || "", model.getValue());

      editor.onDidChangeModelContent(() => {
        var currentValue = editor.getValue();
        state.currentDiffIdentity = buildDiffIdentity({
          path: item.path,
          language: item.language,
          isEditable: item.isEditable,
          originalText: item.originalText || "",
          modifiedText: currentValue,
        });
        renderInlineDiff(editor, item.originalText || "", currentValue);
        postMessage("contentChanged", {
          path: item.path,
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
      state.currentEditorPath = item.path;
      restorePendingViewState(editor, "diff", item.path);
      syncCurrentHunkIndexToViewport(editor);
      state.editors.push(editor, originalModel);
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
      return 0;
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

  function splitLines(text) {
    if (!text) {
      return [];
    }
    const lines = text.split("\n");
    if (lines.length > 0 && lines[lines.length - 1] === "") {
      lines.pop();
    }
    return lines;
  }

  /**
   * Find the changed character sub-range within `source` compared to `other`.
   * Trims the common prefix and suffix, then returns 1-based column positions
   * (UTF-16, matching Monaco column semantics) of the differing middle region.
   * Returns null when source === other or when the changed region is empty.
   *
   * Algorithm mirrors Swift's changedUTF16Range(in:comparedTo:) in RepoViewModel.
   */
  function findChangedCharRange(source, other) {
    if (source === other) {
      return null;
    }
    const sourceChars = Array.from(source);
    const otherChars = Array.from(other);

    let prefixLen = 0;
    while (
      prefixLen < sourceChars.length &&
      prefixLen < otherChars.length &&
      sourceChars[prefixLen] === otherChars[prefixLen]
    ) {
      prefixLen += 1;
    }

    let sourceSuffix = sourceChars.length;
    let otherSuffix = otherChars.length;
    while (
      sourceSuffix > prefixLen &&
      otherSuffix > prefixLen &&
      sourceChars[sourceSuffix - 1] === otherChars[otherSuffix - 1]
    ) {
      sourceSuffix -= 1;
      otherSuffix -= 1;
    }

    // Convert Unicode code-point indices to UTF-16 string lengths (JS native).
    const startColumn = sourceChars.slice(0, prefixLen).join("").length + 1;
    const endColumn = sourceChars.slice(0, sourceSuffix).join("").length + 1;

    if (endColumn <= startColumn) {
      return null;
    }
    return { startColumn, endColumn };
  }

  function buildUnifiedDiffModel(originalText, modifiedText) {
    if (!window.JsDiff || typeof window.JsDiff.diffLines !== "function") {
      throw new Error("JsDiff runtime is not available");
    }

    const parts = window.JsDiff.diffLines(originalText, modifiedText, {
      newlineIsToken: false,
      ignoreWhitespace: false,
    });
    const rows = [];
    const lineNumberMap = new Map();
    const additionDecorations = [];
    const deletionEntries = [];
    // Maps new line number -> { startColumn, endColumn } for paired additions.
    const additionInlineHighlights = new Map();
    let oldLine = 1;
    let newLine = 1;

    for (let index = 0; index < parts.length; index += 1) {
      const part = parts[index];
      const lines = splitLines(part.value);
      const lineCount = lines.length;

      if (part.removed) {
        const nextPart = parts[index + 1];
        const removedLines = lines;
        const addedLines = nextPart && nextPart.added ? splitLines(nextPart.value) : [];
        const anchorModifiedLineNumber = newLine;

        const deletedLines = removedLines.map((content, offset) => ({
          kind: "deletion",
          oldLineNum: oldLine + offset,
          newLineNum: null,
          content,
          inlineHighlight: null,
        }));
        for (const row of deletedLines) {
          rows.push(row);
        }

        // Pair each deleted line with the corresponding added line (same algorithm as
        // Swift's buildInlineHighlights / changedUTF16Range in RepoViewModel).
        const pairCount = Math.min(removedLines.length, addedLines.length);
        for (let pairIndex = 0; pairIndex < pairCount; pairIndex += 1) {
          const delHighlight = findChangedCharRange(removedLines[pairIndex], addedLines[pairIndex]);
          const addHighlight = findChangedCharRange(addedLines[pairIndex], removedLines[pairIndex]);
          if (delHighlight) {
            deletedLines[pairIndex].inlineHighlight = delHighlight;
          }
          if (addHighlight) {
            additionInlineHighlights.set(newLine + pairIndex, addHighlight);
          }
        }

        const modifiedStartLineNumber = addedLines.length > 0 ? newLine : 0;
        const modifiedEndLineNumber = addedLines.length > 0 ? newLine + addedLines.length - 1 : 0;
        deletionEntries.push({
          anchorLine: Math.max(anchorModifiedLineNumber, 1),
          modifiedStartLineNumber,
          modifiedEndLineNumber,
          anchorModifiedLineNumber,
          deletedLines,
          hasAddition: addedLines.length > 0,
        });

        for (let offset = 0; offset < addedLines.length; offset += 1) {
          const lineNumber = newLine + offset;
          const row = {
            kind: "addition",
            oldLineNum: null,
            newLineNum: lineNumber,
            content: addedLines[offset],
          };
          rows.push(row);
          lineNumberMap.set(lineNumber, {
            oldLineNum: null,
            newLineNum: lineNumber,
          });
        }
        if (addedLines.length > 0) {
          additionDecorations.push({
            startLineNumber: newLine,
            endLineNumber: newLine + addedLines.length - 1,
          });
        }

        oldLine += removedLines.length;
        if (nextPart && nextPart.added) {
          newLine += addedLines.length;
          index += 1;
        }
        continue;
      }

      if (part.added) {
        for (let offset = 0; offset < lineCount; offset += 1) {
          const lineNumber = newLine + offset;
          const row = {
            kind: "addition",
            oldLineNum: null,
            newLineNum: lineNumber,
            content: lines[offset],
          };
          rows.push(row);
          lineNumberMap.set(lineNumber, {
            oldLineNum: null,
            newLineNum: lineNumber,
          });
        }
        additionDecorations.push({
          startLineNumber: newLine,
          endLineNumber: newLine + lineCount - 1,
        });
        newLine += lineCount;
        continue;
      }

      for (let offset = 0; offset < lineCount; offset += 1) {
        const oldLineNum = oldLine + offset;
        const newLineNum = newLine + offset;
        const row = {
          kind: "context",
          oldLineNum,
          newLineNum,
          content: lines[offset],
        };
        rows.push(row);
        lineNumberMap.set(newLineNum, {
          oldLineNum,
          newLineNum,
        });
      }
      oldLine += lineCount;
      newLine += lineCount;
    }

    return {
      rows,
      lineNumberMap,
      additionDecorations,
      deletionEntries,
      additionInlineHighlights,
    };
  }

  function buildHunkControlMaps(item) {
    const controls = Array.isArray(item.hunkControls) ? item.hunkControls : [];
    const normalizedControls = controls.map((control) => ({
      path: item.path,
      row: control.row,
      hunkIndex: control.hunkIndex,
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

  function renderInlineDiff(editor, originalText, modifiedText) {
    try {
      const diffModel = buildUnifiedDiffModel(originalText, modifiedText);
      console.log("[MonacoHost] diff updated", {
        path: editor.getModel().uri.path,
        rows: diffModel.rows.length,
        deletions: diffModel.deletionEntries.length,
        additions: diffModel.additionDecorations.length,
        sample: diffModel.rows.slice(0, 6).map((row) => ({
          kind: row.kind,
          old: row.oldLineNum,
          new: row.newLineNum,
        })),
      });
      clearInlineDiff(editor);
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
    if (!state.diffEditor || !state.diffModel) {
      return false;
    }

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
        applyTheme(payload.isDark);
        if (payload.mode === "preview" && payload.preview) {
          reportDebug("loadPayloadPreview", {
            path: payload.preview.path,
            contentLength: (payload.preview.content || "").length,
            currentMode: state.currentMode,
            currentPreviewIdentity: state.currentPreviewIdentity,
          });
          state.pendingHunkActions = null;
          state.pendingLineBlames = null;
          const nextIdentity = buildPreviewIdentity(payload.preview);
          if (state.currentMode === "preview" &&
              state.currentPreviewIdentity === nextIdentity) {
            reportDebug("loadPayloadPreviewSkippedSameIdentity", {
              path: payload.preview.path,
            });
            return;
          }
          renderPreview(payload.preview);
          return;
        }
        if (payload.mode === "diff" && payload.items && payload.items.length > 0) {
          const item = payload.items[0];
          state.pendingHunkActions = {
            path: item.path,
            primaryHunkAction: item.primaryHunkAction || null,
            showsDiscardAction: !!item.showsDiscardAction,
            hunkControls: Array.isArray(item.hunkControls) ? item.hunkControls : [],
          };
          state.pendingLineBlames = Array.isArray(item.lineBlames) ? item.lineBlames : [];

          const nextIdentity = buildDiffIdentity(item);
          if (state.currentMode === "diff" &&
              state.currentDiffIdentity === nextIdentity &&
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
})();
