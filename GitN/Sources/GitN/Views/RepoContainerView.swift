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
        HSplitView {
            SidebarView(viewModel: viewModel)
                .frame(minWidth: 180, idealWidth: sidebarWidth, maxWidth: 350)

            centerPanel

            DetailPanelView(viewModel: viewModel)
                .frame(minWidth: 260, idealWidth: detailWidth, maxWidth: 500)
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
    }

    @ViewBuilder
    private var centerPanel: some View {
        VStack(spacing: 0) {
            repoToolbar
            Divider()

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
