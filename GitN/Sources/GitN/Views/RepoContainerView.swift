import SwiftUI

private let toolbarContentVerticalOffset: CGFloat = 3
private let toolbarAnimatedActiveForeground = Color(nsColor: NSColor(name: nil) { appearance in
    switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
    case .aqua:
        return .controlAccentColor
    default:
        return .white
    }
})

struct RepoContainerView: View {
    let tab: RepoTab
    let isActive: Bool
    @State private var viewModel: RepoViewModel
    @State private var terminalStore: TerminalSessionStore
    @State private var didLoadInitially = false
    @State private var activationTask: Task<Void, Never>?

    @State private var sidebarWidth: CGFloat = 200
    @State private var detailWidth: CGFloat = 400
    @State private var terminalHeight: CGFloat = 300
    @State private var terminalDragStartHeight: CGFloat? = nil

    @State private var showStashMessage = false
    @State private var stashMessage = ""
    @State private var showNewBranch = false
    @State private var newBranchName = ""
    @State private var showIgnoreEditor = false
    @State private var showPullMenu = false
    @State private var showPushMenu = false
    @State private var showHistory = false

    private enum TopBarLayout {
        static let height: CGFloat = 44
        static let horizontalPadding: CGFloat = 10
        static let syncButtonWidth: CGFloat = 46
        static let dividerHeight: CGFloat = 21
    }

    init(tab: RepoTab, isActive: Bool) {
        self.tab = tab
        self.isActive = isActive
        self._viewModel = State(initialValue: RepoViewModel(path: tab.path, name: tab.name))
        self._terminalStore = State(initialValue: TerminalSessionStore(
            repoPath: tab.path,
            useXterm: ProcessInfo.processInfo.environment["GITN_XTERM"] == "1"
        ))
    }

    var body: some View {
        ZStack {
            if viewModel.showConflictMergeView {
                ConflictMergeView(viewModel: viewModel)
            } else {
                VStack(spacing: 0) {
                    unifiedTopBar
                    Divider()

                    HSplitView {
                        SidebarView(viewModel: viewModel)
                            .frame(minWidth: 180, idealWidth: sidebarWidth, maxWidth: 350)

                        centerPanel

                        DetailPanelView(viewModel: viewModel)
                            .frame(minWidth: 260, idealWidth: detailWidth, maxWidth: 800)
                    }
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
                        .font(AppTypography.Chrome.toolbarBody)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
                .padding(32)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }

            if !viewModel.showConflictMergeView,
               let loadingPath = viewModel.conflictMergeLoadingPath {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())

                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Loading conflict...")
                        .font(.system(size: 13, weight: .medium))
                    Text(loadingPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 480)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .background(ChromePalette.panelMutedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .environment(\.hoverTooltipHostActive, isActive)
        .onAppear {
            updateActiveState(isActive)
        }
        .onChange(of: isActive) { _, newValue in
            updateActiveState(newValue)
        }
        .onDisappear {
            activationTask?.cancel()
            viewModel.releaseRetainedResources()
            terminalStore.closeAllSessions()
        }
        .sheet(isPresented: $showStashMessage) {
            stashSheet
        }
        .sheet(isPresented: $showNewBranch) {
            newBranchSheet
        }
        .alert("Force Pull", isPresented: Binding(
            get: { viewModel.showForcePullConfirm },
            set: { viewModel.showForcePullConfirm = $0 }
        )) {
            Button("Force Pull", role: .destructive) {
                Task { await viewModel.performForcePull() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(verbatim: "This will discard all local commits on the current branch and reset it to match the remote branch state (git fetch + git reset --hard @{u}).\n\nThis action cannot be undone. Do you want to continue?")
        }
        .alert("Force Push", isPresented: Binding(
            get: { viewModel.showForcePushConfirm },
            set: { viewModel.showForcePushConfirm = $0 }
        )) {
            Button("Force Push", role: .destructive) {
                Task { await viewModel.performForcePush() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(verbatim: "Force Push will overwrite remote branch history (using the safer --force-with-lease mode).\n\nDo you want to continue?")
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
            Text(verbatim: "Branch '\(viewModel.forceDeleteBranchName)' is not fully merged. Are you sure you want to force delete it? This may cause you to lose commits.")
        }
    }

    private func updateActiveState(_ active: Bool) {
        activationTask?.cancel()

        guard active else {
            deactivateBackgroundWork()
            return
        }

        activationTask = Task {
            if !didLoadInitially {
                await viewModel.loadAll()
                guard !Task.isCancelled else { return }
                didLoadInitially = true
                viewModel.startWatching()
                viewModel.startPeriodicRefresh()
                await viewModel.fetchIfNeeded()
                return
            }

            guard !Task.isCancelled else { return }
            viewModel.startWatching()
            viewModel.startPeriodicRefresh()
            await viewModel.refreshAfterActivation()
        }
    }

    private func deactivateBackgroundWork() {
        viewModel.stopWatching()
        viewModel.stopPeriodicRefresh()
    }

    private func toastView(_ toast: ToastMessage) -> some View {
        HStack(spacing: 10) {
            Image(systemName: toastIcon(toast.style))
                .foregroundStyle(toastColor(toast.style))
                .font(.system(size: 16))

            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(AppTypography.Chrome.toolbarTitle)
                    .foregroundStyle(.white)
                if !toast.detail.isEmpty {
                    Text(toast.detail)
                        .font(AppTypography.Chrome.toolbarMeta)
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
        VStack(spacing: 0) {
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
                    store: terminalStore,
                    isVisible: Binding(
                        get: { viewModel.showTerminal },
                        set: { viewModel.showTerminal = $0 }
                    )
                )
                .frame(height: terminalHeight)
            }
        }
    }

    private var unifiedTopBar: some View {
        HStack(spacing: 12) {
            repoSummary

            Divider()
                .frame(height: TopBarLayout.dividerHeight)

            repoToolbar

            Spacer(minLength: 0)
        }
        .padding(.horizontal, TopBarLayout.horizontalPadding)
        .frame(height: TopBarLayout.height)
        .offset(y: toolbarContentVerticalOffset)
        .background(ChromePalette.toolbarBackground)
    }

    private var repoSummary: some View {
        HStack(spacing: 8) {
                Image(systemName: viewModel.isDetachedHead
                  ? "point.topleft.filled.down.to.point.bottomright.curvepath"
                  : "arrow.triangle.branch")
                .font(AppTypography.Chrome.toolbarIcon)
                .foregroundStyle(viewModel.isDetachedHead ? .orange : .blue)

            VStack(alignment: .leading, spacing: 0) {
                Text(viewModel.repoName)
                    .font(AppTypography.Chrome.toolbarTitle)
                    .lineLimit(1)

                if !viewModel.currentBranch.isEmpty {
                    HStack(spacing: 4) {
                        Text(viewModel.currentBranch)
                            .font(AppTypography.Chrome.toolbarMeta)
                            .foregroundStyle(.secondary)

                        if viewModel.isDetachedHead {
                            Text("detached")
                                .font(AppTypography.Chrome.toolbarBadge)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
        .frame(height: TopBarLayout.height)
        .frame(minWidth: 180, idealWidth: sidebarWidth, maxWidth: 350, alignment: .leading)
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

            historyToolbarButton

            Divider().frame(height: TopBarLayout.dividerHeight).padding(.horizontal, 4)

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
                        .font(AppTypography.Chrome.toolbarMeta)
                        .foregroundStyle(.yellow)
                    Text(conflictBadgeText)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.orange)
                }
                .padding(.trailing, 4)
            }

            Divider().frame(height: TopBarLayout.dividerHeight).padding(.horizontal, 4)

            Button(action: {
                if !viewModel.showTerminal { terminalStore.ensureSession() }
                viewModel.showTerminal.toggle()
            }) {
                toolbarButtonSurface(width: 52) {
                    VStack(spacing: 2) {
                        Image(systemName: viewModel.showTerminal ? "terminal.fill" : "terminal")
                            .font(AppTypography.Chrome.toolbarIcon)
                        Text("Terminal")
                            .font(AppTypography.Chrome.toolbarMiniLabel)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .hoverTooltip("Toggle Terminal")
            // Ctrl-` toggles the terminal (SPEC §8.1). Low-risk, does not
            // collide with app tab shortcuts.
            .keyboardShortcut("`", modifiers: .control)

            Button {
                Task { await viewModel.refreshWithSync() }
            } label: {
                toolbarButtonSurface(width: 44, disabled: viewModel.isLoading) {
                    animatedRefreshLabel(isActive: viewModel.isLoading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)
            .foregroundStyle(viewModel.isLoading ? .secondary : .secondary)
            .hoverTooltip("Refresh\nReload repository status, refs, and history")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Pull Toolbar Button (main button + dropdown triangle)

    private var pullToolbarButton: some View {
        toolbarSplitMenuButton(
            title: "Pull",
            activeOperation: .pull,
            direction: .down,
            action: { Task { await viewModel.performPull() } },
            isMenuPresented: $showPullMenu,
            menuContent: { pullToolbarMenuContent }
        )
        .foregroundStyle(viewModel.operationInProgress ? .tertiary : .secondary)
    }

    // MARK: - Fetch Toolbar Button

    private var fetchToolbarButton: some View {
        Button {
            Task { await viewModel.performFetch() }
        } label: {
            toolbarButtonSurface(width: TopBarLayout.syncButtonWidth, disabled: viewModel.operationInProgress) {
                animatedFetchLabel(isActive: viewModel.activeToolbarOperation == .fetch)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.operationInProgress)
        .foregroundStyle(viewModel.operationInProgress ? .tertiary : .secondary)
    }

    // MARK: - History Toolbar Button (operation history popover)

    /// 「历史」入口：以 popover 打开 `HistoryView`，绑定当前 tab 的
    /// `RepoViewModel.operationHistoryState`，从而自动限定为当前 `Repo_Context`
    /// 的操作历史（Req 4.1 / 4.5）。复用共享 `toolbarButton` 与 `hoverTooltip`
    /// 保持 chrome/按钮语言一致。
    private var historyToolbarButton: some View {
        toolbarButton("History", icon: "clock.arrow.circlepath", disabled: false) {
            showHistory.toggle()
        }
        .popover(isPresented: $showHistory, arrowEdge: .bottom) {
            HistoryView(state: viewModel.operationHistoryState)
        }
        .hoverTooltip("Operation History")
    }

    // MARK: - Push Toolbar Button (main button + dropdown triangle)

    private var pushToolbarButton: some View {
        toolbarSplitMenuButton(
            title: "Push",
            activeOperation: .push,
            direction: .up,
            action: { Task { await viewModel.performPush() } },
            isMenuPresented: $showPushMenu,
            menuContent: { pushToolbarMenuContent }
        )
        .foregroundStyle(viewModel.operationInProgress ? .tertiary : .secondary)
    }

    private func toolbarButton(_ label: String, icon: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            toolbarButtonSurface(width: 44, disabled: disabled) {
                VStack(spacing: 2) {
                    Image(systemName: icon)
                        .font(AppTypography.Chrome.toolbarIcon)
                    Text(verbatim: label)
                        .font(AppTypography.Chrome.toolbarMiniLabel)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .foregroundStyle(disabled ? .tertiary : .secondary)
    }

    private func toolbarSplitMenuButton<MenuContent: View>(
        title: String,
        activeOperation: RepoViewModel.ToolbarOperation?,
        direction: TransferDirection,
        action: @escaping () -> Void,
        isMenuPresented: Binding<Bool>,
        @ViewBuilder menuContent: @escaping () -> MenuContent
    ) -> some View {
        let totalWidth = TopBarLayout.syncButtonWidth + 14
        return RepoToolbarSplitHoverSurface(
            width: totalWidth,
            height: TopBarLayout.height,
            isEnabled: !viewModel.operationInProgress
        ) {
            Button(action: action) {
                HStack(spacing: 0) {
                    animatedTransferLabel(
                        title: title,
                        systemImage: direction == .down ? "arrow.down.to.line" : "arrow.up.to.line",
                        direction: direction,
                        isActive: viewModel.activeToolbarOperation == activeOperation
                    )
                    .frame(width: TopBarLayout.syncButtonWidth, height: TopBarLayout.height)

                    Spacer(minLength: 0)
                }
                .frame(width: totalWidth, height: TopBarLayout.height)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.operationInProgress)
            .overlay(alignment: .trailing) {
                Button {
                    isMenuPresented.wrappedValue.toggle()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .scaleEffect(x: 0.82, y: 1.0)
                        .frame(width: 14, height: TopBarLayout.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.operationInProgress)
                .popover(isPresented: isMenuPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                    toolbarMenuPopover {
                        menuContent()
                    }
                }
            }
        }
    }

    private var pullToolbarMenuContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("点击 Pull 按钮时执行")
                .font(AppTypography.Chrome.toolbarBody.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)

            ForEach(RepoViewModel.PullMode.allCases) { mode in
                Button {
                    viewModel.defaultPullMode = mode
                    showPullMenu = false
                } label: {
                    HStack(spacing: 8) {
                        Text(mode.label)
                        Spacer(minLength: 8)
                        if viewModel.defaultPullMode == mode {
                            Image(systemName: "checkmark")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.clear)
            }

            Divider()
                .padding(.vertical, 2)

            Button {
                showPullMenu = false
                viewModel.showForcePullConfirm = true
            } label: {
                Label("Force Pull (reset to remote)", systemImage: "exclamationmark.triangle")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
        .frame(width: 260)
    }

    private var pushToolbarMenuContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                showPushMenu = false
                viewModel.showForcePushConfirm = true
            } label: {
                Label("Force Push (--force-with-lease)", systemImage: "exclamationmark.triangle")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
        .frame(width: 250)
    }

    private func toolbarMenuPopover<Content: View>(
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(8)
    }

    private func toolbarButtonSurface<Content: View>(
        width: CGFloat,
        disabled: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        RepoToolbarHoverSurface(width: width, height: TopBarLayout.height, isEnabled: !disabled) {
            content()
        }
    }

    fileprivate enum TransferDirection {
        case up
        case down
    }

    private func animatedTransferLabel(
        title: String,
        systemImage: String,
        direction: TransferDirection,
        isActive: Bool
    ) -> some View {
        ToolbarTransferAnimationView(
            title: title,
            systemImage: systemImage,
            direction: direction,
            isActive: isActive
        )
    }

    private func animatedFetchLabel(isActive: Bool) -> some View {
        ToolbarFetchAnimationView(title: "Fetch", isActive: isActive)
    }

    private func animatedRefreshLabel(isActive: Bool) -> some View {
        ToolbarRefreshAnimationView(title: "Refresh", isActive: isActive)
    }

    // MARK: - More Menu

    private var moreMenu: some View {
        HStack(spacing: 0) {
            Divider().frame(height: TopBarLayout.dividerHeight).padding(.horizontal, 4)

            Menu {
                Button {
                    showIgnoreEditor = true
                } label: {
                    Label("编辑 .gitignore", systemImage: "doc.text")
                }
            } label: {
                toolbarButtonSurface(width: 28) {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 12))
                }
            }
            .menuStyle(.borderlessButton)
            .foregroundStyle(.secondary)
            .frame(width: 28, height: TopBarLayout.height)
            .contentShape(Rectangle())
            .hoverTooltip("More\nAdditional repository actions")
            .fixedSize()
            .sheet(isPresented: $showIgnoreEditor) {
                GitIgnoreEditorView(
                    repoPath: viewModel.repoPath,
                    isPresented: $showIgnoreEditor,
                    onSave: {
                        Task { @MainActor in
                            await viewModel.refreshAfterWorkingTreeMutation()
                        }
                    }
                )
            }
        }
    }

    // MARK: - Host Key Banner

    private var hostKeyBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Verify SSH host: \(viewModel.hostKeyHost)")
                .font(AppTypography.Chrome.toolbarBody)
            if let candidate = viewModel.hostKeyCandidate {
                Text("Compare these fingerprints with the server administrator or a trusted source before trusting these keys.")
                    .font(.caption)
                ForEach(candidate.keys, id: \.fingerprint) { key in
                    Text("\(key.algorithm)  \(key.fingerprint)")
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            HStack {
                Button(viewModel.hostKeyCandidate == nil ? "Review Keys" : "Trust These Keys") {
                    Task { await viewModel.acceptHostKey() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isScanningHostKeys)
                if viewModel.isScanningHostKeys { ProgressView().controlSize(.small) }
                Button("Cancel") { viewModel.rejectHostKey() }
                    .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor).opacity(0.7))
    }

    // MARK: - Push Upstream Banner

    private var pushUpstreamBanner: some View {
        HStack(spacing: 8) {
            Text(verbatim: "What remote/branch should \"\(viewModel.currentBranch)\" push to and pull from?")
                .font(AppTypography.Chrome.toolbarBody)
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

            FocusTextField(titleKey: "branch", text: Binding(
                get: { viewModel.pushUpstreamBranch },
                set: { viewModel.pushUpstreamBranch = $0 }
            ), cornerRadius: 6, horizontalPadding: 8, verticalPadding: 4)
            .font(AppTypography.Chrome.toolbarBody)
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
            FocusTextField(titleKey: "Branch name", text: $newBranchName)
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
            FocusTextField(titleKey: "Stash message (optional)", text: $stashMessage)
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

private struct ToolbarTransferAnimationView: View {
    let title: String
    let systemImage: String
    let direction: RepoContainerView.TransferDirection
    let isActive: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: isActive ? 1.0 / 30.0 : 0.5, paused: !isActive)) { context in
            let progress = animationProgress(at: context.date)
            let shimmer = shimmerProgress(at: context.date)

            let ghostTravel: CGFloat = direction == .down ? 5 : -5
            let drift: CGFloat = direction == .down ? 1.2 : -1.2
            let ghostOpacity = isActive ? max(0, sin(progress * .pi)) * 0.28 : 0
            let iconOffset = isActive ? drift * CGFloat(sin(progress * .pi * 2)) : 0
            let iconScale = isActive ? 1 + 0.025 * sin(progress * .pi * 2) : 1
            let glowOpacity = isActive ? 0.18 + 0.08 * sin(progress * .pi * 2) : 0

            toolbarAnimatedContainer(
                shimmerProgress: shimmer,
                glowOpacity: glowOpacity,
                icon: {
                    ZStack {
                        Image(systemName: systemImage)
                            .font(AppTypography.Chrome.toolbarIcon)
                            .offset(y: ghostTravel * CGFloat(progress))
                            .opacity(ghostOpacity)
                            .blur(radius: 0.2)

                        Image(systemName: systemImage)
                            .font(AppTypography.Chrome.toolbarIcon)
                            .offset(y: iconOffset)
                            .scaleEffect(iconScale)
                    }
                }
            ) {
                Text(verbatim: title)
                    .font(.system(size: 9, weight: isActive ? .semibold : .regular))
            }
        }
    }
}

private struct ToolbarFetchAnimationView: View {
    let title: String
    let isActive: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: isActive ? 1.0 / 30.0 : 0.5, paused: !isActive)) { context in
            let progress = animationProgress(at: context.date)
            let shimmer = shimmerProgress(at: context.date)
            let dropProgress = max(0, sin(progress * .pi))
            let ghostOpacity = isActive ? dropProgress * 0.24 : 0
            let iconOffset = isActive ? -1.2 + 1.8 * dropProgress : 0
            let iconScale = isActive ? 1 + 0.03 * dropProgress : 1
            let glowOpacity = isActive ? 0.15 + 0.1 * dropProgress : 0

            toolbarAnimatedContainer(
                shimmerProgress: shimmer,
                glowOpacity: glowOpacity,
                icon: {
                    ZStack {
                        Image(systemName: "arrow.down.circle")
                            .font(AppTypography.Chrome.toolbarIcon)
                            .offset(y: -4 + 6 * CGFloat(progress))
                            .opacity(ghostOpacity)
                            .blur(radius: 0.25)

                        Image(systemName: "arrow.down.circle")
                            .font(AppTypography.Chrome.toolbarIcon)
                            .offset(y: iconOffset)
                            .scaleEffect(iconScale)
                    }
                }
            ) {
                Text(verbatim: title)
                    .font(.system(size: 9, weight: isActive ? .semibold : .regular))
            }
        }
    }
}

private struct ToolbarRefreshAnimationView: View {
    let title: String
    let isActive: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: isActive ? 1.0 / 30.0 : 0.5, paused: !isActive)) { context in
            let progress = animationProgress(at: context.date)
            let eased = 1 - pow(1 - progress, 3)
            let rotation = isActive ? eased * 320 : 0
            let iconScale = isActive ? 1 + 0.022 * sin(progress * .pi * 2) : 1
            let glowOpacity = isActive ? 0.18 + 0.07 * sin(progress * .pi * 2) : 0

            toolbarAnimatedContainer(
                shimmerProgress: 0,
                glowOpacity: glowOpacity,
                showsShimmer: false,
                icon: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(AppTypography.Chrome.toolbarIcon)
                        .rotationEffect(.degrees(rotation))
                        .scaleEffect(iconScale)
                        .drawingGroup()
                }
            ) {
                Text(verbatim: title)
                    .font(.system(size: 9, weight: isActive ? .semibold : .regular))
            }
        }
    }
}

@ViewBuilder
private func toolbarAnimatedContainer<Icon: View, Label: View>(
    shimmerProgress: Double,
    glowOpacity: Double,
    showsShimmer: Bool = true,
    @ViewBuilder icon: () -> Icon,
    @ViewBuilder label: () -> Label
) -> some View {
    VStack(spacing: 2) {
        icon()
            .frame(height: 14)

        label()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .foregroundStyle(
        glowOpacity > 0
            ? AnyShapeStyle(toolbarAnimatedActiveForeground)
            : AnyShapeStyle(Color.secondary)
    )
    .overlay {
        if showsShimmer {
            LinearGradient(
                colors: [
                    .clear,
                    Color.white.opacity(glowOpacity > 0 ? 0.14 + glowOpacity * 0.22 : 0),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 18)
            .offset(x: (shimmerProgress - 0.5) * 24)
            .blendMode(.plusLighter)
            .mask {
                VStack(spacing: 2) {
                    icon()
                        .frame(height: 14)
                    label()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private func animationProgress(at date: Date) -> Double {
    let cycle = 1.45
    return date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
}

private func shimmerProgress(at date: Date) -> Double {
    let cycle = 1.9
    return date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
}

private struct RepoToolbarHoverSurface<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    let isEnabled: Bool
    @ViewBuilder let content: () -> Content

    @State private var isHovering = false

    var body: some View {
        content()
            .frame(width: width, height: height)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering && isEnabled ? ChromePalette.toolbarHoverBackground : .clear)
            )
            .onHover { isHovering = $0 }
    }
}

private struct RepoToolbarSplitHoverSurface<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    let isEnabled: Bool
    @ViewBuilder let content: () -> Content

    @State private var isHovering = false

    var body: some View {
        content()
            .frame(width: width, height: height)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering && isEnabled ? ChromePalette.toolbarHoverBackground : .clear)
            )
            .onHover { isHovering = $0 }
    }
}
