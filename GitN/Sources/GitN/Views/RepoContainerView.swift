import SwiftUI

struct RepoContainerView: View {
    let tab: RepoTab
    @State private var viewModel: RepoViewModel

    @State private var sidebarWidth: CGFloat = 220
    @State private var detailWidth: CGFloat = 320
    @State private var terminalHeight: CGFloat = 200

    @State private var showStashMessage = false
    @State private var stashMessage = ""
    @State private var showNewBranch = false
    @State private var newBranchName = ""

    init(tab: RepoTab) {
        self.tab = tab
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
                        .frame(minWidth: 260, idealWidth: detailWidth, maxWidth: 500)
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
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.3), value: viewModel.toastMessage)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                        if viewModel.toastMessage?.id == toast.id {
                            viewModel.dismissToast()
                        }
                    }
                }
            }
        }
        .task {
            await viewModel.loadAll()
            viewModel.startWatching()
        }
        .sheet(isPresented: $showStashMessage) {
            stashSheet
        }
        .sheet(isPresented: $showNewBranch) {
            newBranchSheet
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showFileHistory },
            set: { if !$0 { viewModel.closeFileHistory() } }
        )) {
            FileHistoryView(viewModel: viewModel)
                .frame(minWidth: 800, minHeight: 550)
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
                        .lineLimit(2)
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
                Divider()
                TerminalPanelView(
                    repoPath: viewModel.repoPath,
                    isVisible: Binding(
                        get: { viewModel.showTerminal },
                        set: { viewModel.showTerminal = $0 }
                    )
                )
                .frame(minHeight: 100, idealHeight: terminalHeight, maxHeight: 400)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { viewModel.showTerminal.toggle() }) {
                    Image(systemName: "terminal")
                        .symbolVariant(viewModel.showTerminal ? .fill : .none)
                }
                .help("Toggle Terminal")
            }

            ToolbarItem(placement: .automatic) {
                Button(action: { Task { await viewModel.loadAll() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
        }
    }

    // MARK: - Repo Toolbar (Pull / Push / Fetch / Stash / Pop)

    private var repoToolbar: some View {
        HStack(spacing: 2) {
            toolbarButton("Pull", icon: "arrow.down.to.line", disabled: viewModel.operationInProgress) {
                Task { await viewModel.performPull() }
            }
            toolbarButton("Push", icon: "arrow.up.to.line", disabled: viewModel.operationInProgress) {
                Task { await viewModel.performPush() }
            }
            toolbarButton("Fetch", icon: "arrow.triangle.2.circlepath", disabled: viewModel.operationInProgress) {
                Task { await viewModel.performFetch() }
            }
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

            Divider().frame(height: 16).padding(.horizontal, 4)

            // Branch indicator
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(viewModel.currentBranch)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)

            Spacer()

            if viewModel.operationInProgress {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 4)
            }

            if let error = viewModel.operationError {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
                .padding(.trailing, 4)
                .onTapGesture { viewModel.operationError = nil }
            }

            if viewModel.isRebaseConflict {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow)
                    Text("REBASE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.orange)
                }
                .padding(.trailing, 4)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.controlBackgroundColor).opacity(0.5))
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
