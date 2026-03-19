import SwiftUI

struct GitIgnoreEditorView: View {
    let repoPath: String
    @Binding var isPresented: Bool

    @State private var text: String = ""
    @State private var isSaving = false

    private var ignoreURL: URL {
        URL(fileURLWithPath: repoPath).appendingPathComponent(".gitignore")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text(".gitignore")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Button {
                    save()
                } label: {
                    Text("保存")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isSaving)

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.windowBackgroundColor))

            Divider()

            TextEditor(text: $text)
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 500, minHeight: 400)
        .onAppear { load() }
    }

    private func load() {
        if let content = try? String(contentsOf: ignoreURL, encoding: .utf8) {
            text = content
        } else {
            text = ""
        }
    }

    private func save() {
        isSaving = true
        do {
            try text.write(to: ignoreURL, atomically: true, encoding: .utf8)
        } catch {
            // ignore write errors silently
        }
        isSaving = false
        isPresented = false
    }
}
