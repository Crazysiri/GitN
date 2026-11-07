// Run after Scripts/build_monaco.sh: swift Monaco/tests/conflict-wkwebview-smoke.swift
import AppKit
import WebKit

final class Smoke: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKScriptMessageHandlerWithReply {
    private var view: WKWebView!
    private var directory: URL!
    private var actions = [String]()
    private var edits = 0
    private var scriptErrors = [String]()
    private var servedWorkers = Set<String>()

    func start() {
        let messages = WKUserContentController()
        messages.add(self, name: "monaco")
        messages.add(self, name: "smoke")
        messages.add(self, name: "debug")
        messages.addScriptMessageHandler(self, contentWorld: .page, name: "monacoWorker")
        // This CLI WebView is hidden; WebKit suspends animation frames in that state.
        // Use timer-backed frames to exercise the host's coalesced scroll callback.
        messages.addUserScript(WKUserScript(source: "window.requestAnimationFrame = callback => setTimeout(() => callback(performance.now()), 0); window.cancelAnimationFrame = clearTimeout;", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        messages.addUserScript(WKUserScript(source: "window.addEventListener('error', e => window.webkit.messageHandlers.debug.postMessage({message:e.message, filename:e.filename, line:e.lineno, column:e.colno, error:String(e.error), stack:e.error?.stack || '', target:e.target?.tagName || '', src:e.target?.src || ''}), true); window.addEventListener('unhandledrejection', e => window.webkit.messageHandlers.debug.postMessage({rejection:String(e.reason)})); const NativeWorker = window.Worker; window.Worker = function(url, options) { window.webkit.messageHandlers.debug.postMessage({workerStart:String(url)}); const worker = new NativeWorker(url, options); worker.addEventListener('error', e => window.webkit.messageHandlers.debug.postMessage({workerError:String(url), message:e.message || '', filename:e.filename || ''})); return worker; }; window.Worker.prototype = NativeWorker.prototype;", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let config = WKWebViewConfiguration()
        config.userContentController = messages
        view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 720), configuration: config)
        view.navigationDelegate = self
        directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/GitN/Resources/Monaco").standardizedFileURL
        view.loadFileURL(directory.appendingPathComponent("index.html"), allowingReadAccessTo: directory)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript(#"""
        (async () => {
          const check = (ok, reason) => { if (!ok) throw new Error(reason); };
          const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
          const load = payload => window.gitnMonaco.loadPayload(btoa(JSON.stringify(payload)));
          const pointerClick = (button, label) => {
            check(button && button.tabIndex >= 0, label + ' is a focusable button');
            const rect = button.getBoundingClientRect();
            const x = rect.x + 15, y = rect.y + rect.height / 2;
            const target = document.elementFromPoint(x, y);
            if (target !== button) window.webkit.messageHandlers.debug.postMessage({stage:'miss', label,
              rect:[rect.x, rect.y, rect.width, rect.height], hit:target?.className,
              parent:target?.parentElement?.className});
            check(target === button, label + ' receives pointer hit');
            for (const [type, buttons] of [['mousedown', 1], ['mouseup', 0], ['click', 0]]) {
              target.dispatchEvent(new MouseEvent(type, {bubbles: true, cancelable: true,
                clientX: x, clientY: y, button: 0, buttons}));
            }
          };
          const rows = Array.from({length: 140}, (_, i) => 'line ' + i);
          const text = rows.join('\n');
          const block = {id: 0, ours: [50, 55], theirs: [50, 51], output: [50, 52], ancestorLength: 5,
            selectedOurs: [], selectedTheirs: [], allOurs: false, allTheirs: false, resolved: false};
          const conflict = {path: 'merge.txt', language: 'plaintext', oursLabel: 'Current',
            theirsLabel: 'Incoming', oursText: text, theirsText: text, outputText: text,
            blocks: [block], origins: rows.map(() => 'common'), externalRevision: 0,
            navigationID: 0, currentBlock: 0, acknowledgedEdit: 0};
          const payload = {mode: 'conflict', isDark: true, sourceID: 'smoke-session', conflict};
          load(payload);
          window.webkit.messageHandlers.debug.postMessage({stage:'created'});
          check(window.monaco.editor.getEditors().length === 3, 'three Monaco editors');
          check(document.querySelectorAll('.gitn-merge-block-header').length === 3, 'three aligned blocks');
          const editors = window.monaco.editor.getEditors();
          const ours = editors.find(editor => editor.getModel().uri.authority === 'ours');
          const theirs = editors.find(editor => editor.getModel().uri.authority === 'theirs');
          const output = editors.find(editor => editor.getModel().uri.authority === 'output');
          check(ours && theirs && output, 'three independent models');
          check([ours, theirs, output].every(editor =>
            !editor.getOption(monaco.editor.EditorOption.stickyScroll).enabled),
            'merge panes do not cover block actions with sticky headers');
          check(output.getValue() === text, 'output has document text');
          const zoneCalls = {ours: 0, theirs: 0, output: 0};
          for (const [side, editor] of [['ours', ours], ['theirs', theirs], ['output', output]]) {
            const original = editor.changeViewZones.bind(editor);
            editor.changeViewZones = callback => { zoneCalls[side]++; return original(callback); };
          }
          load({...payload, isDark: false});
          check(Object.values(zoneCalls).every(count => count === 0), 'theme-only update reuses merge zones');
          load(payload);
          check(!document.querySelector('.gitn-merge-spacer'), 'no artificial alignment rows');
          const originalHeight = [ours, theirs, output].map(editor => editor.getScrollHeight());
          check(Math.max(...originalHeight) - Math.min(...originalHeight) < 2,
            'equal text lengths keep equal compact heights despite unequal block lengths');
          const expandedRows = [...rows.slice(0, 52), ...Array.from({length: 10}, (_, i) => 'chosen ' + i),
            ...rows.slice(52)];
          load({...payload, conflict: {...conflict, outputText: expandedRows.join('\n'),
            blocks: [{...block, output: [50, 62]}], origins: expandedRows.map(() => 'common')}});
          check(output.getScrollHeight() >= originalHeight[2] + 10 * 19 - 2,
            'selected output lines add only their own content height');
          check(ours.getScrollHeight() === originalHeight[0] &&
            theirs.getScrollHeight() === originalHeight[1] && !document.querySelector('.gitn-merge-spacer'),
            'output growth does not pad source panes');
          load(payload);
          ours.setScrollTop(0);
          await pause(80);
          const beforeTheirs = theirs.getScrollTop(), beforeOutput = output.getScrollTop();
          const beforeOurs = ours.getScrollTop();
          ours.setScrollTop(800);
          await pause(80);
          window.webkit.messageHandlers.debug.postMessage({stage:'scrolled', beforeOurs, beforeTheirs, beforeOutput,
            scroll: [ours.getScrollTop(), theirs.getScrollTop(), output.getScrollTop()],
            visibility: document.visibilityState,
            height: [ours.getLayoutInfo().height, theirs.getLayoutInfo().height, output.getLayoutInfo().height],
            editorHeight: [...document.querySelectorAll('.gitn-merge-editor')].map(el => el.getBoundingClientRect().height)});
          check(theirs.getScrollTop() > beforeTheirs + 200 &&
            output.getScrollTop() > beforeOutput + 200, 'block-relative scroll sync');
          const beforeReverse = ours.getScrollTop();
          output.setScrollTop(1200);
          await pause(80);
          check(ours.getScrollTop() > beforeReverse + 200, 'output-to-source scroll sync');
          ours.setScrollTop(900);
          await pause(80);
          const glyph = document.querySelector('.gitn-merge-ours .gitn-merge-glyph');
          window.webkit.messageHandlers.debug.postMessage({stage:'glyph', count:
            document.querySelectorAll('.gitn-merge-ours .gitn-merge-glyph').length,
            rect: glyph && [glyph.getBoundingClientRect().x, glyph.getBoundingClientRect().y,
              glyph.getBoundingClientRect().width, glyph.getBoundingClientRect().height]});
          check(glyph, 'source line glyph is rendered');
          check(getComputedStyle(glyph, '::after').content === '""' &&
            getComputedStyle(glyph, '::after').borderStyle === 'solid',
            'source line shows an unchecked checkbox');
          const glyphRect = glyph.getBoundingClientRect();
          glyph.dispatchEvent(new MouseEvent('mousedown', {bubbles: true, cancelable: true,
            clientX: glyphRect.x + 8, clientY: glyphRect.y + 8, button: 0, buttons: 1}));
          pointerClick(document.querySelector('.gitn-merge-ours .gitn-merge-block-toggle'), 'A block');
          pointerClick(document.querySelector('.gitn-merge-theirs .gitn-merge-block-toggle'), 'B block');
          check(output.getAction('undo') && output.getAction('redo'), 'native merge undo actions');
          output.trigger('smoke', 'undo');
          output.trigger('smoke', 'redo');
          output.executeEdits('smoke', [{range: new monaco.Range(1, 1, 1, 1), text: 'X'}]);
          window.webkit.messageHandlers.debug.postMessage({stage:'edited'});
          check(output.getValue().startsWith('X'), 'local output edit');
          load({...payload, conflict: {...conflict, outputText: 'stale', acknowledgedEdit: 0}});
          check(output.getValue().startsWith('X'), 'old native echo does not roll back typing');
          const updated = {...conflict, outputText: output.getValue(), acknowledgedEdit: 1,
            blocks: [{...block, selectedOurs: [0], resolved: true}], externalRevision: 1};
          load({...payload, isDark: false, conflict: updated});
          window.webkit.messageHandlers.debug.postMessage({stage:'updated'});
          check(document.body.classList.contains('theme-light'), 'light theme follows app');
          check(window.monaco.editor.getEditors().includes(output) && output.getModel().getValue().startsWith('X'),
            'metadata updates reuse editor and model');
          ours.revealLineInCenter(51);
          await pause(80);
          const checkedGlyph = document.querySelector('.gitn-merge-ours .gitn-merge-glyph.selected');
          check(checkedGlyph && getComputedStyle(checkedGlyph, '::after').content.includes('✓'),
            'selected source line shows a checked checkbox');
          const emptyConflict = {...updated, oursText: '',
            blocks: [{...block, ours: [0, 0], theirs: [50, 51], output: [50, 52], ancestorLength: 10}]};
          load({...payload, sourceID: 'next-session', conflict: emptyConflict});
          window.webkit.messageHandlers.debug.postMessage({stage:'source-switched'});
          await pause(80);
          check(window.monaco.editor.getEditors().length === 3, 'source switch disposes former editors');
          check(document.querySelector('.gitn-merge-ours .gitn-merge-block-toggle')?.textContent === 'Take empty A',
            'empty side action stays in compact header');
          check(!document.querySelector('.gitn-merge-spacer'), 'empty side has no padding rows');
          pointerClick(document.querySelector('.gitn-merge-ours .gitn-merge-block-toggle'), 'empty A block');
          const emptyOurs = window.monaco.editor.getEditors().find(editor => editor.getModel().uri.authority === 'ours');
          const withAncestor = emptyOurs.getScrollHeight();
          load({...payload, sourceID: 'next-session', conflict: {...emptyConflict,
            blocks: [{...emptyConflict.blocks[0], ancestorLength: 1}]}});
          check(withAncestor === emptyOurs.getScrollHeight(),
            'ancestor length cannot add blank visual rows');
          load({mode: 'preview', sourceID: 'next-session', isDark: false,
            preview: {path: 'after.txt', language: 'plaintext', content: 'after', isEditable: true}});
          window.webkit.messageHandlers.debug.postMessage({stage:'preview'});
          check(window.monaco.editor.getEditors().length === 1 && !document.querySelector('.gitn-merge-shell'),
            'leaving conflict disposes three-way host');
          window.webkit.messageHandlers.smoke.postMessage({ok: true});
        })().catch(error => window.webkit.messageHandlers.smoke.postMessage({error: String(error)}));
        void 0;
        """#) { _, error in
            if let error { print("EVAL ERROR: \(error)"); exit(1) }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("CONFLICT NAVIGATION ERROR: \(error)"); exit(1)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("CONFLICT PROVISIONAL ERROR: \(error)"); exit(1)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "debug" {
            print("SCRIPT DEBUG: \(message.body)")
            if let body = message.body as? [String: Any] {
                if let error = body["message"] as? String { scriptErrors.append(error) }
                if let error = body["rejection"] as? String { scriptErrors.append(error) }
                if let error = body["workerError"] as? String { scriptErrors.append(error) }
            }
            return
        }
        if message.name == "smoke" {
            print("Conflict WKWebView smoke: \(message.body), actions: \(actions), edits: \(edits)")
            let result = message.body as? [String: Any]
            print("Workers: \(servedWorkers.sorted()), script errors: \(scriptErrors)")
            exit(result?["ok"] as? Bool == true &&
                 actions.filter({ $0 == "ours" }).count == 2 &&
                 actions.filter({ $0 == "theirs" }).count == 1 &&
                 ["oursLine", "undo", "redo"].allSatisfy(actions.contains) &&
                 edits > 0 && scriptErrors.isEmpty ? 0 : 1)
        }
        guard let body = message.body as? [String: Any], let event = body["event"] as? String else { return }
        if event == "hunkAction", let action = body["action"] as? String { actions.append(action) }
        if event == "contentChanged" { edits += 1 }
        if event == "error" {
            print("HOST ERROR: \(body)")
            scriptErrors.append(body["message"] as? String ?? "Unknown host error")
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any], let filename = body["filename"] as? String,
              ["editor.worker.js", "json.worker.js", "css.worker.js", "html.worker.js", "ts.worker.js"].contains(filename) else {
            replyHandler(nil, "Invalid worker"); return
        }
        do {
            replyHandler(try String(contentsOf: directory.appendingPathComponent(filename), encoding: .utf8), nil)
            servedWorkers.insert(filename)
        }
        catch { replyHandler(nil, "Missing worker") }
    }
}

_ = NSApplication.shared
let smoke = Smoke()
smoke.start()
DispatchQueue.main.asyncAfter(deadline: .now() + 60) { print("Conflict WKWebView smoke timed out"); exit(1) }
RunLoop.main.run()
