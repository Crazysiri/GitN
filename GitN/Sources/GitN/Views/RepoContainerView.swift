import SwiftUI

struct RepoContainerView: View {
    let tab: RepoTab
    let isActive: Bool
    @State private var viewModel: RepoViewModel

    @State private var sidebarWidth: CGFloat = 200
    @State private var detailWidth: CGFloat = 400
    @State private var terminalHeight: CGFloat = 300
    @State private var terminalDragStartHeight: CGFloat? = nil

    @State private var showStashMessage = false
    @State private var stashMessage = ""
    @State private var showNewBranch = false
    @State private var newBranchName = ""
    @State private var showIgnoreEditor = false

    init(tab: RepoTab, isActive: Bool) {
        self.tab = tab
        self.isActive = isActive
        self._viewModel = State(initialValue: RepoViewModel(path: tab.path, name: tab.name))
    }

    var body: some View {
        ZStack {
            if viewModel.showConflictMergeView {
                ConflictMergeView(viewModel: viewModel)
            } else {
                HSplitView {
                    SidebarView(viewModel: viewModel)
                        .frame(minWidth: 180, idealWidth: sidebarWidth, maxWidth: 350)

                    centerPanel

                    DetailPanelView(viewModel: viewModel)
                        .frame(minWidth: 260, idealWidth: detailWidth, maxWidth: 800)
                }
            }

            // Toast overlay
            if let toast = viewModel.toastMessage {
                VStack {
                    Spacer()
                    HStack {
                        toastView(toast)
                            .padding(.leading, 16)
                            .padding(.bottom, 16)
                        Spacer()
                    }
                }
                .id(toast.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.3), value: viewModel.toastMessage)
            }

            // Global MR merging overlay — blocks all interaction
            if viewModel.isMRMerging {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .contentShape(Rectangle()) // absorb all clicks
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text(viewModel.mrMergingStatus)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
                .padding(32)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .task {
            await viewModel.loadAll()
            viewModel.startWatching()
            viewModel.startPeriodicRefresh()
        }
        .onAppear {
            // When tab becomes visible (including when switching tabs), perform a throttled fetch
            Task {
                await viewModel.fetchIfNeeded()
            }
        }
        .onDisappear {
            viewModel.stopPeriodicRefresh()
        }
        .sheet(isPresented: $showStashMessage) {
            stashSheet
        }
        .sheet(isPresented: $showNewBranch) {
            newBranchSheet
        }
        .alert(
            "Branch Not Fully Merged",
            isPresented: Binding(
                get: { viewModel.showForceDeleteBranchPrompt },
                set: { if !$0 { viewModel.showForceDeleteBranchPrompt = false } }
            )
        ) {
            Button("Force Delete", role: .destructive) {
                // Capture the name synchronously before the alert dismissal
                // clears it via the binding setter.
                let name = viewModel.forceDeleteBranchName
                viewModel.forceDeleteBranchName = ""
                Task { await viewModel.performDeleteBranch(name, force: true) }
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelForceDeleteBranch()
            }
        } message: {
            Text("Branch '\(viewModel.forceDeleteBranchName)' is not fully merged. Are you sure you want to force delete it? This may cause you to lose commits.")
        }
    }

    private func toastView(_ toast: ToastMessage) -> some View {
        HStack(spacing: 10) {
            Image(systemName: toastIcon(toast.style))
                .foregroundStyle(toastColor(toast.style))
                .font(.system(size: 16))

            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                if !toast.detail.isEmpty {
                    Text(toast.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

            Spacer()

            Button(action: { viewModel.dismissToast() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 380)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.darkGray).opacity(0.95))
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        )
    }

    private func toastIcon(_ style: ToastMessage.ToastStyle) -> String {
        switch style {
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func toastColor(_ style: ToastMessage.ToastStyle) -> Color {
        switch style {
        case .error: return .red
        case .warning: return .yellow
        case .success: return .green
        case .info: return .blue
        }
    }

    @ViewBuilder
    private var centerPanel: some View {
        ZStack {
            VStack(spacing: 0) {
                repoToolbar
                Divider()

                if viewModel.showHostKeyPrompt {
                    hostKeyBanner
                    Divider()
                }

                if viewModel.showPushUpstreamPrompt {
                    pushUpstreamBanner
                    Divider()
                }

                GraphView(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if viewModel.showTerminal {
                    ZStack {
                        Divider()
                        Color.clear
                            .frame(height: 8)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 1)
                                    .onChanged { value in
                                        if terminalDragStartHeight == nil {
                                            terminalDragStartHeight = terminalHeight
                                        }
                                        let newH = (terminalDragStartHeight ?? terminalHeight) - value.translation.height
                                        terminalHeight = max(100, min(700, newH))
                                    }
                                    .onEnded { _ in
                                        terminalDragStartHeight = nil
                                    }
                            )
                            .onHover { inside in
                                if inside { NSCursor.resizeUpDown.push() }
                                else { NSCursor.pop() }
                            }
                    }
                    .frame(height: 8)

                    TerminalPanelView(
                        repoPath: viewModel.repoPath,
                        isVisible: Binding(
                            get: { viewModel.showTerminal },
                            set: { viewModel.showTerminal = $0 }
                        )
                    )
                    .frame(height: terminalHeight)
                }
            }

            if viewModel.isFileInspectorPresented {
                FileInspectorOverlayView(viewModel: viewModel)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
    }

    // MARK: - Repo Toolbar (Pull / Push / Fetch / Stash / Pop)

    private var repoToolbar: some View {
        HStack(spacing: 2) {
            pullToolbarButton
            pushToolbarButton
            fetchToolbarButton

            toolbarButton("Branch", icon: "arrow.triangle.branch", disabled: viewModel.operationInProgress) {
                showNewBranch = true
            }

            Divider().frame(height: 16).padding(.horizontal, 4)

            toolbarButton("Stash", icon: "tray.and.arrow.down", disabled: viewModel.operationInProgress) {
                showStashMessage = true
            }
            toolbarButton("Pop", icon: "tray.and.arrow.up", disabled: viewModel.operationInProgress || viewModel.stashes.isEmpty) {
                Task { await viewModel.performStashPop() }
            }

            moreMenu

            Spacer()

            if viewModel.operationInProgress {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 4)
            }


            if viewModel.isInConflict {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow)
                    Text(conflictBadgeText)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.orange)
                }
                .padding(.trailing, 4)
            }

            Divider().frame(height: 16).padding(.horizontal, 4)

            Button(action: { viewModel.showTerminal.toggle() }) {
                VStack(spacing: 1) {
                    Image(systemName: viewModel.showTerminal ? "terminal.fill" : "terminal")
                        .font(.system(size: 13))
                    Text("Terminal")
                        .font(.system(size: 9))
                }
                .frame(width: 52, height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Toggle Terminal")

            toolbarButton("Refresh", icon: "arrow.clockwise", disabled: viewModel.isLoading) {
                Task { await viewModel.refreshWithSync() }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Pull Toolbar Button (main button + dropdown triangle)

    @State private var showPullMenu = false

    private var pullToolbarButton: some View {
        HStack(spacing: 0) {
            // Main Pull button – executes the currently selected default mode
            Button {
                Task { await viewModel.performPull() }
            } label: {
                VStack(spacing: 1) {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 13))
                    Text("Pull")
                        .font(.system(size: 9))
                }
                .frame(width: 38, height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.operationInProgress)

            // Dropdown triangle
            Menu {
                // Pull mode selection (checkmark only, doesn't execute)
                Section("点击 Pull 按钮时执行") {
                    ForEach(RepoViewModel.PullMode.allCases) { mode in
                        Button {
                            viewModel.defaultPullMode = mode
                        } label: {
                            HStack {
                                Text(mode.label)
                                if viewModel.defaultPullMode == mode {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }

                Divider()

                // Force Pull – shows confirmation, no checkmark
                Button(role: .destructive) {
                    viewModel.showForcePullConfirm = true
                } label: {
                    Label("Force Pull (reset to remote)", systemImage: "exclamationmark.triangle")
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 4, weight: .semibold))
                    .frame(width: 10, height: 34)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 12, height: 34)
            .disabled(viewModel.operationInProgress)
        }
        .foregroundStyle(viewModel.operationInProgress ? .tertiary : .secondary)
        .alert("Force Pull", isPresented: Binding(
            get: { viewModel.showForcePullConfirm },
            set: { viewModel.showForcePullConfirm = $0 }
        )) {
            Button("Force Pull", role: .destructive) {
                Task { await viewModel.performForcePull() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将丢弃本地分支的所有提交，重置为远程分支状态 (git fetch + git reset --hard @{u})。\n\n此操作不可撤销，确定继续？")
        }
    }

    // MARK: - Fetch Toolbar Button

    private var fetchToolbarButton: some View {
        Button {
            Task { await viewModel.performFetch() }
        } label: {
            VStack(spacing: 1) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 13))
                Text("Fetch")
                    .font(.system(size: 9))
            }
            .frame(width: 38, height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.operationInProgress)
        .foregroundStyle(viewModel.operationInProgress ? .tertiary : .secondary)
    }

    // MARK: - Push Toolbar Button (main button + dropdown triangle)

    private var pushToolbarButton: some View {
        HStack(spacing: 0) {
            // Main Push button – always does normal push
            Button {
                Task { await viewModel.performPush() }
            } label: {
                VStack(spacing: 1) {
                    Image(systemName: "arrow.up.to.line")
                        .font(.system(size: 13))
                    Text("Push")
                        .font(.system(size: 9))
                }
                .frame(width: 38, height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.operationInProgress)

            // Dropdown triangle
            Menu {
                Button(role: .destructive) {
                    viewModel.showForcePushConfirm = true
                } label: {
                    Label("Force Push (--force-with-lease)", systemImage: "exclamationmark.triangle")
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 4, weight: .semibold))
                    .frame(width: 10, height: 34)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 12, height: 34)
            .disabled(viewModel.operationInProgress)
        }
        .foregroundStyle(viewModel.operationInProgress ? .tertiary : .secondary)
        .alert("Force Push", isPresented: Binding(
            get: { viewModel.showForcePushConfirm },
            set: { viewModel.showForcePushConfirm = $0 }
        )) {
            Button("Force Push", role: .destructive) {
                Task { await viewModel.performForcePush() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("Force Push 会覆盖远程分支历史 (使用 --force-with-lease 安全模式)。\n\n确定继续？")
        }
    }

    private func toolbarButton(_ label: String, icon: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                Text(label)
                    .font(.system(size: 9))
            }
            .frame(width: 44, height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .foregroundStyle(disabled ? .tertiary : .secondary)
    }

    // MARK: - More Menu

    private var moreMenu: some View {
        HStack(spacing: 0) {
            Divider().frame(height: 16).padding(.horizontal, 4)

            Menu {
                Button {
                    showIgnoreEditor = true
                } label: {
                    Label("编辑 .gitignore", systemImage: "doc.text")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13))
                    .frame(width: 28, height: 34)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .foregroundStyle(.secondary)
            .fixedSize()
            .sheet(isPresented: $showIgnoreEditor) {
                GitIgnoreEditorView(repoPath: viewModel.repoPath, isPresented: $showIgnoreEditor)
            }
        }
    }

    // MARK: - Host Key Banner

    private var hostKeyBanner: some View {
        HStack(spacing: 8) {
            Text("The authenticity of host '\(viewModel.hostKeyHost)' can't be established. Answering yes will permanently add '\(viewModel.hostKeyHost)' to the list of known hosts. Are you sure you want to continue?")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer()

            Button("Yes") {
                Task { await viewModel.acceptHostKey() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button("No") {
                viewModel.rejectHostKey()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.controlBackgroundColor).opacity(0.7))
    }

    // MARK: - Push Upstream Banner

    private var pushUpstreamBanner: some View {
        HStack(spacing: 8) {
            Text("What remote/branch should \"\(viewModel.currentBranch)\" push to and pull from?")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)

            Picker("", selection: Binding(
                get: { viewModel.pushUpstreamRemote },
                set: { viewModel.pushUpstreamRemote = $0 }
            )) {
                ForEach(viewModel.remotes) { remote in
                    Text(remote.name).tag(remote.name)
                }
            }
            .labelsHidden()
            .frame(width: 100)
            .controlSize(.small)

            Text("/")
                .foregroundStyle(.secondary)

            TextField("branch", text: Binding(
                get: { viewModel.pushUpstreamBranch },
                set: { viewModel.pushUpstreamBranch = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11))
            .frame(width: 120)
            .controlSize(.small)

            Button("Submit") {
                let remote = viewModel.pushUpstreamRemote.trimmingCharacters(in: .whitespaces)
                let branch = viewModel.pushUpstreamBranch.trimmingCharacters(in: .whitespaces)
                guard !remote.isEmpty, !branch.isEmpty else { return }
                Task { await viewModel.performPushWithUpstream(remote: remote, branch: branch) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button("Cancel") {
                viewModel.cancelPushUpstreamPrompt()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.controlBackgroundColor).opacity(0.7))
    }

    // MARK: - New Branch Sheet

    private var newBranchSheet: some View {
        VStack(spacing: 12) {
            Text("New Branch")
                .font(.headline)
            TextField("Branch name", text: $newBranchName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
            HStack {
                Button("Cancel") {
                    showNewBranch = false
                    newBranchName = ""
                }
                .keyboardShortcut(.cancelAction)
                Button("Create") {
                    let name = newBranchName.trimmingCharacters(in: .whitespaces)
                    showNewBranch = false
                    newBranchName = ""
                    guard !name.isEmpty else { return }
                    Task { await viewModel.performCreateBranch(name: name) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newBranchName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }

    private var conflictBadgeText: String {
        switch viewModel.conflictType {
        case .rebase: return "REBASE"
        case .merge: return "MERGE"
        case .stashApply: return "STASH"
        case nil: return "CONFLICT"
        }
    }

    // MARK: - Stash Sheet

    private var stashSheet: some View {
        VStack(spacing: 12) {
            Text("Save Stash")
                .font(.headline)
            TextField("Stash message (optional)", text: $stashMessage)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
            HStack {
                Button("Cancel") {
                    showStashMessage = false
                    stashMessage = ""
                }
                .keyboardShortcut(.cancelAction)
                Button("Stash") {
                    let msg = stashMessage.isEmpty ? nil : stashMessage
                    showStashMessage = false
                    stashMessage = ""
                    Task { await viewModel.performStashSave(message: msg) }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }
}
