import SwiftUI

struct NewTabView: View {
    @Environment(AppModel.self) private var appModel
    @State private var showClone = false

    var body: some View {
        HStack(spacing: 0) {
            // 左侧：Repositories 区域
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    Text("Repositories")
                        .font(.system(size: 32, weight: .bold))

                    Spacer()

                    if !appModel.tabs.isEmpty {
                        Button {
                            appModel.closeNewTabView()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 24, height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(ChromePalette.chromeButtonFill)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(ChromePalette.chromeButtonBorder, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .hoverTooltip("Close")
                    }
                }
                .padding(.top, 40)
                .padding(.leading, 40)
                .padding(.trailing, 40)

                // Open, Clone 按钮
                HStack(spacing: 16) {
                    Button(action: {
                        appModel.openRepository()
                    }) {
                        NewTabActionButtonLabel(
                            title: "Open",
                            systemImage: "folder",
                            role: .prominent
                        )
                    }
                    .buttonStyle(.plain)

                    Button(action: { showClone = true }) {
                        NewTabActionButtonLabel(
                            title: "Clone",
                            systemImage: "arrow.down.to.line",
                            role: .secondary
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 40)
                .sheet(isPresented: $showClone) {
                    CloneSheetView(isPresented: $showClone)
                }

                // Recent 标题
                Text("Recent")
                    .font(.system(size: 18, weight: .semibold))
                    .padding(.top, 20)
                    .padding(.leading, 40)

                // Recent 列表
                if appModel.recentRepos.isEmpty {
                    Text("No recent repositories")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))
                        .padding(.top, 8)
                        .padding(.leading, 40)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(appModel.recentRepos, id: \.path) { repo in
                                RecentRepoRow(repo: repo)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // 右侧：可以留空或添加其他内容
            Spacer()
                .frame(width: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
        .alert(
            "Not a Git Repository",
            isPresented: Binding(
                get: { appModel.pendingGitInit != nil },
                set: { if !$0 { appModel.pendingGitInit = nil } }
            ),
            presenting: appModel.pendingGitInit
        ) { pending in
            Button("Initialize", role: .none) {
                appModel.initAndOpenRepository(path: pending.path, name: pending.name)
                appModel.pendingGitInit = nil
            }
            Button("Cancel", role: .cancel) {
                appModel.pendingGitInit = nil
            }
        } message: { pending in
            Text("\"\(pending.name)\" is not a Git repository. Would you like to initialize it with `git init`?")
        }
    }
}

private struct NewTabActionButtonLabel: View {
    enum Role {
        case prominent
        case secondary
    }

    let title: String
    let systemImage: String
    let role: Role

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(foregroundColor)
        .frame(width: 120, height: 36)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onHover { isHovering = $0 }
    }

    private var foregroundColor: Color {
        switch role {
        case .prominent:
            return .white
        case .secondary:
            return .primary
        }
    }

    private var backgroundColor: Color {
        switch role {
        case .prominent:
            return isHovering ? Color.accentColor.opacity(0.88) : Color.accentColor
        case .secondary:
            return isHovering ? Color(.controlBackgroundColor) : Color(.windowBackgroundColor)
        }
    }

    private var borderColor: Color {
        switch role {
        case .prominent:
            return isHovering ? Color.accentColor.opacity(0.95) : Color.accentColor.opacity(0.82)
        case .secondary:
            return isHovering ? Color.primary.opacity(0.20) : Color.primary.opacity(0.12)
        }
    }
}

// MARK: - Recent Repo Row

private struct RecentRepoRow: View {
    @Environment(AppModel.self) private var appModel
    let repo: SavedRepo
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: {
                appModel.openRepository(path: repo.path, name: repo.name)
            }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(repo.name)
                        .foregroundStyle(.blue)
                        .font(.system(size: 14, weight: .medium))
                    Text(repo.path)
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            Button {
                appModel.removeFromRecent(path: repo.path)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0)
            .padding(.trailing, 48)
        }
        .background(isHovering ? Color(.selectedContentBackgroundColor).opacity(0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 40)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Clone Sheet

struct CloneSheetView: View {
    @Environment(AppModel.self) private var appModel
    @Binding var isPresented: Bool

    @State private var urlString = ""
    @State private var destinationDir = ""
    @State private var folderName = ""
    @State private var isCloning = false
    @State private var errorMessage: String?

    private var destinationPath: String {
        guard !destinationDir.isEmpty, !folderName.isEmpty else { return "" }
        return (destinationDir as NSString).appendingPathComponent(folderName)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Image(systemName: "arrow.down.to.line.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text("Clone Repository")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(.windowBackgroundColor))

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                // URL field
                VStack(alignment: .leading, spacing: 6) {
                    Text("Repository URL")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("https://github.com/user/repo.git", text: $urlString)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: urlString) { _, newURL in
                            let name = repoName(from: newURL)
                            if !name.isEmpty {
                                folderName = name
                            }
                        }
                }

                // Destination directory
                VStack(alignment: .leading, spacing: 6) {
                    Text("Clone into")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Text(destinationDir.isEmpty ? "Choose a directory…" : destinationDir)
                            .font(.system(size: 13))
                            .foregroundStyle(destinationDir.isEmpty ? .tertiary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color(.textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.3), lineWidth: 0.5))

                        Button("Choose…") {
                            chooseDirectory()
                        }
                        .controlSize(.small)
                    }
                }

                // Folder name
                VStack(alignment: .leading, spacing: 6) {
                    Text("Folder name")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("repo-name", text: $folderName)
                        .textFieldStyle(.roundedBorder)
                }

                // Full path preview
                if !destinationPath.isEmpty {
                    Text(destinationPath)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }

                // Error
                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)

            Divider()

            // Buttons
            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)
                .disabled(isCloning)

                Button {
                    startClone()
                } label: {
                    HStack(spacing: 6) {
                        if isCloning {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isCloning ? "Cloning…" : "Clone")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canClone || isCloning)
                .keyboardShortcut(.return)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(.windowBackgroundColor))
        }
        .frame(width: 480)
    }

    private var canClone: Bool {
        !urlString.trimmingCharacters(in: .whitespaces).isEmpty &&
        !destinationDir.isEmpty &&
        !folderName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a directory to clone into"
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            destinationDir = url.path
        }
    }

    private func startClone() {
        errorMessage = nil
        isCloning = true
        let url = urlString.trimmingCharacters(in: .whitespaces)
        let dest = destinationPath
        let name = folderName.trimmingCharacters(in: .whitespaces)

        Task {
            do {
                try await appModel.cloneRepository(urlString: url, destinationPath: dest, name: name)
                isPresented = false
            } catch {
                errorMessage = error.localizedDescription
            }
            isCloning = false
        }
    }

    private func repoName(from urlString: String) -> String {
        var s = urlString.trimmingCharacters(in: .whitespaces)
        if s.hasSuffix(".git") { s = String(s.dropLast(4)) }
        if let i = s.lastIndex(of: "/") {
            s = String(s[s.index(after: i)...])
        } else if let i = s.lastIndex(of: ":") {
            s = String(s[s.index(after: i)...])
        }
        return s
    }
}
