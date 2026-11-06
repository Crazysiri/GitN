// Run after Scripts/build_monaco.sh: swift Monaco/tests/wkwebview-smoke.swift
import AppKit
import WebKit

final class Smoke: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKScriptMessageHandlerWithReply {
    var view: WKWebView!
    var workerDirectory: URL!
    var workerFailures = 0
    var servedWorkers = Set<String>()
    func start() {
        let controller = WKUserContentController()
        controller.add(self, name: "monaco")
        controller.add(self, name: "smoke")
        controller.add(self, name: "smokeDebug")
        controller.addScriptMessageHandler(self, contentWorld: .page, name: "monacoWorker")
        controller.addUserScript(WKUserScript(
            source: """
              window.addEventListener('error', e => window.webkit.messageHandlers.smokeDebug.postMessage({message: e.message || '', filename: e.filename || '', line: e.lineno || 0, column: e.colno || 0, target: e.target?.tagName || '', source: e.target?.src || ''}), true);
              const NativeWorker = window.Worker;
              window.Worker = function(url, options) {
                window.webkit.messageHandlers.smokeDebug.postMessage({workerStart: String(url)});
                const worker = new NativeWorker(url, options);
                worker.addEventListener('error', e => window.webkit.messageHandlers.smokeDebug.postMessage({workerError: String(url), message: e.message || '', filename: e.filename || ''}));
                return worker;
              };
              window.Worker.prototype = NativeWorker.prototype;
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        let config = WKWebViewConfiguration()
        config.userContentController = controller
        view = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 600), configuration: config)
        view.navigationDelegate = self
        let dir = CommandLine.arguments.count > 1
            ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).standardizedFileURL
            : URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("../../Sources/GitN/Resources/Monaco").standardizedFileURL
        workerDirectory = dir
        view.loadFileURL(dir.appendingPathComponent("index.html"), allowingReadAccessTo: dir)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript(#"""
        (async () => {
          const check = (value, label) => { if (!value) throw new Error(label); };
          const result = await window.gitnDiffScheduler.run('one\ntwo\n', 'one\nnew\n');
          check(result.lineNumberMap instanceof Map && result.deletionEntries.length === 1, 'worker diff');
          const load = payload => window.gitnMonaco.loadPayload(btoa(JSON.stringify(payload)));
          const preview = (path, content) => ({mode: 'preview', preview: {path, content, language: 'plaintext', isEditable: true}});
          load(preview('a.txt', 'first'));
          const editor = window.monaco.editor.getEditors()[0];
          const firstModel = editor.getModel();
          load(preview('b.txt', 'second'));
          check(window.monaco.editor.getEditors()[0] === editor && !firstModel.isDisposed(), 'preview model cache');
          const secondModel = editor.getModel();
          load(preview('b.txt', 'updated'));
          check(editor.getModel() === secondModel && editor.getValue() === 'updated', 'same-path preview reuse');
          const waitForDiff = async () => {
            for (let i = 0; i < 160 && !document.querySelector('.gitn-diff-status').hidden; ++i) {
              await new Promise(resolve => setTimeout(resolve, 50));
            }
            check(document.querySelector('.gitn-diff-status').hidden, 'diff decorations ready');
          };
          const smallDiff = (originalText, modifiedText) => ({mode: 'diff', isDark: true, items: [{
            path: 'small.md', originalText, modifiedText, language: 'markdown', isEditable: false
          }]});
          load(smallDiff('keep\nremoved red line\n', 'keep\n'));
          await waitForDiff();
          let deleted = document.querySelector('.gitn-deletion-line-content');
          check(deleted && deleted.textContent === 'removed red line', 'pure deletion text');
          let block = document.querySelector('.gitn-deletion-content-block');
          let red = getComputedStyle(block).backgroundColor.match(/[\d.]+/g).map(Number);
          check(red[0] > red[1] && red[0] > red[2], 'dark red deletion background');
          load({...smallDiff('keep\nremoved red line\n', 'keep\n'), isDark: false});
          block = document.querySelector('.gitn-deletion-content-block');
          red = getComputedStyle(block).backgroundColor.match(/[\d.]+/g).map(Number);
          check(red[0] > red[1] && red[0] > red[2], 'light red deletion background');
          load(smallDiff('one\ntwo\n', 'one\nnew\n'));
          await waitForDiff();
          deleted = document.querySelector('.gitn-deletion-line-content');
          check(deleted && deleted.textContent === 'two', 'replacement keeps removed text');
          await new Promise(resolve => setTimeout(resolve, 100));
          const replacementBlock = document.querySelector('.gitn-deletion-content-block');
          const replacementRect = replacementBlock.getBoundingClientRect();
          const shellRect = document.querySelector('.single-diff-shell').getBoundingClientRect();
          check(replacementRect.width > 0 && replacementRect.height > 0 &&
            replacementRect.top >= shellRect.top && replacementRect.bottom <= shellRect.bottom,
            'replacement deletion must be inside viewport');
          const packageBefore = '{\n  "name": "gitn-monaco",\n  "version": "1.0.0",\n  "private": true,\n  "scripts": {\n    "build": "webpack --mode production",\n    "build:dev": "webpack --mode development"\n  }\n}\n';
          const packageAfter = packageBefore.replace('webpack --mode production', 'webpack --config webpack.worker.config.js && webpack --mode production');
          load({mode: 'diff', isDark: false, items: [{path: 'package.json', originalText: packageBefore,
            modifiedText: packageAfter, language: 'json', isEditable: true}]});
          await waitForDiff();
          const packageBlock = document.querySelector('.gitn-deletion-content-block');
          const packageRect = packageBlock?.getBoundingClientRect();
          const packageRed = getComputedStyle(packageBlock).backgroundColor.match(/[\d.]+/g).map(Number);
          const packageHit = packageRect && document.elementFromPoint(packageRect.x + 20, packageRect.y + packageRect.height / 2);
          check(packageRed[0] > packageRed[1] && packageRed[0] > packageRed[2] &&
            packageRed[3] >= 0.35, 'light deletion has visible red contrast');
          check(packageRect && packageRect.top >= 0 && packageRect.bottom <= 600 &&
            packageHit?.closest('.gitn-deletion-content-block'), 'package deletion visibly hit-testable');
          const numberBefore = Array.from({length: 110}, (_, i) => 'line ' + (i + 1)).join('\n') + '\n';
          const numberAfter = numberBefore.replace('line 100\n', 'changed 100\n');
          load(smallDiff(numberBefore, numberAfter));
          await waitForDiff();
          window.monaco.editor.getEditors()[0].revealLine(100);
          await new Promise(resolve => setTimeout(resolve, 100));
          load(smallDiff(numberBefore, numberAfter));
          const oldNumber = [...document.querySelectorAll('.gitn-gutter-old-number')].find(n => n.textContent === '100');
          const oldNumberRect = oldNumber?.getBoundingClientRect();
          check(oldNumberRect && oldNumberRect.width >= 30 &&
            window.monaco.editor.getEditors()[0].getOption(window.monaco.editor.EditorOption.lineNumbersMinChars) >= 10,
            'three-digit old and new number columns must fit');
          const lines = Array.from({length: 12000}, (_, i) => 'line ' + i).join('\n') + '\n';
          const diff = (path, text) => ({mode: 'diff', items: [{path, originalText: lines, modifiedText: text, language: 'plaintext', isEditable: true}]});
          load(diff('large.txt', lines + 'one\n'));
          const diffEditor = window.monaco.editor.getEditors()[0];
          load(diff('latest.txt', lines + 'two\n'));
          check(window.monaco.editor.getEditors()[0] === diffEditor, 'diff reuse');
          check(diffEditor.getValue().endsWith('two\n'), 'text first');
          check(diffEditor.getOption(window.monaco.editor.EditorOption.lineNumbersMinChars) >= 12,
            'large file keeps enough width for five-digit line numbers');
          await waitForDiff();
          const model = diffEditor.getModel();
          const largeLines = model.getLineCount();
          load(diff('latest.txt', lines + 'two\n'));
          check(diffEditor.getModel() === model, 'metadata preserves model');
          check(window.monaco.editor.getModels().length <= 8, 'bounded model cache');
          const measurements = [];
          for (const count of [1000, 10000, 50000]) {
            const text = Array.from({length: count}, (_, i) => 'const line' + i + ' = ' + i + ';').join('\n') + '\n';
            const beginPreview = performance.now();
            load(preview('perf-' + count + '.txt', text));
            const previewModelMs = performance.now() - beginPreview;
            check(window.monaco.editor.getEditors()[0].getModel().getLineCount() === count + 1, 'preview model lines');
            const beginDiff = performance.now();
            load({mode: 'diff', items: [{path: 'perf-' + count + '.txt', originalText: text,
              modifiedText: text + 'one change\n', language: 'plaintext', isEditable: false}]});
            const diffModelMs = performance.now() - beginDiff;
            await waitForDiff();
            measurements.push({lines: count, previewModelMs, diffModelMs, diffReadyMs: performance.now() - beginDiff});
          }
          load({mode: 'preview', preview: {path: 'language.ts',
            content: 'const answer: number = 42;\n', language: 'typescript', isEditable: true}});
          const tsModel = window.monaco.editor.getEditors()[0].getModel();
          const getTypeScriptWorker = await window.monaco.languages.typescript.getTypeScriptWorker();
          await getTypeScriptWorker(tsModel.uri);
          window.webkit.messageHandlers.smoke.postMessage({ok: true, rows: result.rows.length,
            largeLines, measurements});
        })().catch(error => window.webkit.messageHandlers.smoke.postMessage({error: String(error)}));
        void 0;
        """#) { _, error in
            if let error { print("EVAL ERROR: \(error)"); exit(1) }
        }
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "smokeDebug" {
            print("WKWebView script diagnostic: \(message.body)")
            if let body = message.body as? [String: Any], body["workerError"] != nil { workerFailures += 1 }
            return
        }
        if message.name == "smoke" {
            print("WKWebView smoke: \(message.body)")
            let result = message.body as? [String: Any]
            let workersReady = servedWorkers.isSuperset(of: ["editor.worker.js", "json.worker.js", "ts.worker.js"])
            print("Monaco workers: \(servedWorkers.sorted()), failures: \(workerFailures)")
            exit(result?["ok"] as? Bool == true && workersReady && workerFailures == 0 ? 0 : 1)
        }
        if let body = message.body as? [String: Any], body["event"] as? String == "error" {
            print("HOST ERROR: \(body)")
        }
    }
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        guard let request = message.body as? [String: Any],
              let filename = request["filename"] as? String,
              ["editor.worker.js", "json.worker.js", "css.worker.js",
               "html.worker.js", "ts.worker.js"].contains(filename) else {
            replyHandler(nil, "Invalid worker")
            return
        }
        do {
            let source = try String(contentsOf: workerDirectory.appendingPathComponent(filename), encoding: .utf8)
            servedWorkers.insert(filename)
            replyHandler(source, nil)
        } catch {
            replyHandler(nil, "Missing worker resource")
        }
    }
}
_ = NSApplication.shared
let smoke = Smoke()
smoke.start()
DispatchQueue.main.asyncAfter(deadline: .now() + 120) { print("WKWebView smoke timed out"); exit(1) }
RunLoop.main.run()
