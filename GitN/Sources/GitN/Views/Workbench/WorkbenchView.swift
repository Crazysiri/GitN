import SwiftUI

struct WorkbenchView: View {
    let tab: RepoTab
    let isActive: Bool
    @Environment(AppModel.self) private var appModel
    @State private var model: WorkbenchModel
    @State private var page: WorkbenchPage = .sessions
    @State private var showNewTask = false
    @State private var taskPendingDeletion: WorkbenchTask?
    @State private var worktreePendingRemoval: WorktreeInfo?

    init(tab: RepoTab, isActive: Bool) {
        self.tab = tab
        self.isActive = isActive
        _model = State(initialValue: WorkbenchModel(path: tab.path))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                navigation
                Divider()
                switch page {
                case .sessions:
                    WorkbenchSessionsView(model: model, openGit: { openGit(path: $0) }, openTask: { page = .tasks })
                case .overview: overview
                case .tasks: taskWorkspace
                case .worktrees: worktreeList
                }
            }
        }
        .background(ChromePalette.panelBackground)
        .environment(\.hoverTooltipHostActive, isActive)
        .task(id: isActive) {
            guard isActive else { return }
            await model.refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                await model.importSessionEvents()
            }
        }
        .onChange(of: model.selectedTaskID) { _, _ in
            model.selectedWorktreePath = nil
            Task { await model.loadChanges() }
        }
        .onChange(of: model.selectedWorktreePath) { _, _ in Task { await model.loadChanges() } }
        .onChange(of: page) { _, value in
            model.showsTaskChanges = value == .tasks
            Task { await model.loadChanges() }
        }
        .sheet(isPresented: $showNewTask) { NewWorkbenchTaskSheet(model: model) { page = .tasks } }
        .alert("Workbench", isPresented: Binding(
            get: { model.error != nil }, set: { if !$0 { model.error = nil } }
        )) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .confirmationDialog("Delete task record?", isPresented: Binding(
            get: { taskPendingDeletion != nil }, set: { if !$0 { taskPendingDeletion = nil } }
        ), titleVisibility: .visible) {
            if let task = taskPendingDeletion {
                Button("Delete Task", role: .destructive) { Task { await model.deleteTask(task) } }
            }
        } message: { Text("Worktrees, branches and files will be kept.") }
        .confirmationDialog("Remove Worktree directory?", isPresented: Binding(
            get: { worktreePendingRemoval != nil }, set: { if !$0 { worktreePendingRemoval = nil } }
        ), titleVisibility: .visible) {
            if let worktree = worktreePendingRemoval {
                Button("Remove Worktree", role: .destructive) {
                    let paths = appModel.tabs.map(\.path)
                    Task { await model.removeWorktree(worktree, openPaths: paths) }
                }
            }
        } message: { Text("Only a clean, unlocked Worktree can be removed. The branch and task records will be kept.") }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Label(tab.name, systemImage: "square.stack.3d.up")
                .font(.system(size: 13, weight: .semibold))
            Text("Workbench").foregroundStyle(.secondary)
            Spacer()
            if let date = model.refreshedAt {
                Text("Updated \(date.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Button { Task { await model.refresh() } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(model.isLoading)
            .hoverTooltip("Refresh tasks and Git state")
            Button("Open in Git") { openGit(path: tab.path) }
            Button { showNewTask = true } label: { Label("New Task", systemImage: "plus") }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(ChromePalette.toolbarBackground)
    }

    private var navigation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WORKBENCH").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 4)
            ForEach(WorkbenchPage.allCases) { item in
                Button { page = item } label: {
                    HStack {
                        Label(item.rawValue, systemImage: item.symbol)
                        Spacer(minLength: 4)
                        if item == .sessions { Text("\(model.sessions.count)").foregroundStyle(.secondary) }
                        if item == .tasks { Text("\(model.tasks.count)").foregroundStyle(.secondary) }
                        if item == .worktrees { Text("\(model.worktrees.count)").foregroundStyle(.secondary) }
                    }
                    .font(.system(size: 12, weight: page == item ? .semibold : .regular))
                    .padding(10)
                    .background(page == item ? Color.accentColor.opacity(0.13) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                Label("Local tasks", systemImage: "internaldrive")
                    .font(.system(size: 11, weight: .medium))
                Text("Sessions arrive through Hooks. Refresh for Git state; task stages are manual.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Text(tab.path).font(.system(size: 10)).foregroundStyle(.tertiary)
                    .textSelection(.enabled).lineLimit(3)
            }
            .padding(10)
        }
        .padding(8)
        .frame(width: 168)
        .background(ChromePalette.panelMutedBackground)
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Project Overview").font(.system(size: 24, weight: .semibold))
                Text("Tasks and Worktrees for \(tab.name)").foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    metric("Tasks", value: model.tasks.count, symbol: "checklist")
                    metric("In Progress", value: model.tasks.filter { $0.stage == .working }.count, symbol: "play.circle")
                    metric("Ready for Review", value: model.tasks.filter { $0.stage == .review }.count, symbol: "eye")
                }
                Text("Recent Tasks").font(.headline)
                if model.tasks.isEmpty {
                    emptyState("Start with a task", message: "Create a task with a dedicated Worktree, or associate an existing one.")
                }
                ForEach(model.tasks.prefix(8)) { task in
                    Button {
                        model.selectedTaskID = task.id
                        page = .tasks
                    } label: {
                        HStack {
                            Label(task.title, systemImage: "checklist")
                            Spacer()
                            Text(task.stage.rawValue).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                        }.padding(14).background(ChromePalette.panelMutedBackground, in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain)
                }
            }.padding(28)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func metric(_ title: String, value: Int, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.system(size: 12)).foregroundStyle(.secondary)
            Text("\(value)").font(.system(size: 28, weight: .semibold))
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(18).background(ChromePalette.panelMutedBackground, in: RoundedRectangle(cornerRadius: 10))
    }

    private var taskWorkspace: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Tasks").font(.headline)
                    Spacer()
                    if model.isLoading { ProgressView().controlSize(.small) }
                }.padding(16)
                Divider()
                if model.tasks.isEmpty {
                    emptyState("No tasks yet", message: "Use New Task to get started.")
                } else {
                    List(selection: $model.selectedTaskID) {
                        ForEach(model.tasks) { task in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(task.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                                Text(task.stage.rawValue).font(.system(size: 11)).foregroundStyle(.secondary)
                                Text("\(task.agent.rawValue) · \(task.worktrees.count) Worktree(s)")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }.padding(.vertical, 8).tag(task.id)
                        }
                    }.listStyle(.sidebar)
                }
                Spacer(minLength: 0)
            }.frame(minWidth: 210, idealWidth: 250, maxWidth: 350)
            if let task = model.selectedTask {
                taskDetail(task)
                    .frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyState("Your task workspace", message: "Select a task to inspect its Worktrees and changes.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func taskDetail(_ task: WorkbenchTask) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(task.title).font(.system(size: 22, weight: .semibold)).textSelection(.enabled)
                        Text(model.sessions(for: task).isEmpty ? "Intended Agent: \(task.agent.rawValue) · No session associated" : "\(model.sessions(for: task).count) associated session(s)")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        ForEach(WorkbenchStage.allCases) { stage in
                            Button(stage.rawValue) { Task { await model.setStage(stage, task: task) } }
                        }
                        Divider()
                        Button("Delete Task…", role: .destructive) { taskPendingDeletion = task }
                    } label: { Text(task.stage.rawValue) }
                }
                ForEach(model.sessions(for: task)) { session in
                    Button {
                        model.selectedSessionID = session.id
                        page = .sessions
                    } label: { Label(session.displayTitle, systemImage: "bubble.left.and.bubble.right") }
                }
                if !task.notes.isEmpty { Text(task.notes).textSelection(.enabled).foregroundStyle(.secondary) }
                Divider()
                HStack {
                    Text("Worktrees").font(.headline)
                    Spacer()
                    Menu("Associate Existing") {
                        ForEach(model.worktrees.filter { !$0.isBare && !$0.isPrunable }) { worktree in
                            Button(worktree.branchName ?? worktree.path) { Task { await model.associate(worktree, task: task) } }
                                .disabled(task.worktrees.contains { $0.path == worktree.path })
                        }
                    }
                }
                ForEach(task.worktrees) { link in
                    Button {
                        model.selectedWorktreePath = link.path
                    } label: {
                        HStack {
                            Image(systemName: model.selectedLink?.path == link.path ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(URL(fileURLWithPath: link.path).lastPathComponent).fontWeight(.medium)
                                Text(link.path).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                                if !model.worktrees.contains(where: { $0.path == link.path }) {
                                    Text("Worktree unavailable — task record retained").font(.caption).foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                        }.padding(12)
                            .background(ChromePalette.panelMutedBackground, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
                HStack {
                    Text("Changes").font(.headline)
                    Spacer()
                    if let link = model.selectedLink {
                        Button("Open Worktree in Git") { openGit(path: link.path) }
                            .disabled(!model.worktrees.contains { $0.path == link.path })
                    }
                }
                Text("Compared with the commit captured at association time; includes any pre-existing changes. Untracked contents are not included in the patch.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if let link = model.selectedLink {
                    Text("Base: \(link.baseCommit.map { String($0.prefix(12)) } ?? "Unborn branch")")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }
                if let changes = model.changes {
                    Text("Captured \(changes.capturedAt.formatted(date: .omitted, time: .standard)) · Refresh for latest state")
                        .font(.caption).foregroundStyle(.secondary)
                    codeBlock(changes.status.isEmpty ? "Working directory clean" : changes.status)
                    if !changes.patch.isEmpty { codeBlock(changes.patch) }
                    else { Text("No tracked-file patch against this baseline.").foregroundStyle(.secondary) }
                } else {
                    Text(model.changesError ?? "No change preview available. Refresh to retry.")
                        .foregroundStyle(.secondary).textSelection(.enabled)
                }
            }.padding(24)
        }
    }

    private var worktreeList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Worktrees").font(.system(size: 24, weight: .semibold))
                Text("Worktrees created in your AI tools are discovered by Git. Multiple sessions may use the same directory.")
                    .foregroundStyle(.secondary)
                ForEach(model.worktrees) { worktree in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label(worktree.branchName ?? "Detached HEAD", systemImage: "arrow.triangle.branch").font(.headline)
                            if worktree.isMain { Text("Main").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Button("Open in Git") { openGit(path: worktree.path) }
                                .disabled(worktree.isBare || worktree.isPrunable)
                            Button("Remove…", role: .destructive) { worktreePendingRemoval = worktree }
                                .disabled(worktree.isMain || worktree.isLocked || worktree.isPrunable || worktree.path == tab.path)
                        }
                        Text(worktree.path).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
                        Text("HEAD \(worktree.headOID.map { String($0.prefix(12)) } ?? "—")")
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        ForEach(model.sessions(for: worktree)) { session in
                            Button {
                                model.selectedSessionID = session.id
                                page = .sessions
                            } label: { Label(session.displayTitle, systemImage: "bubble.left") }
                        }
                        if worktree.isLocked { Label("Locked", systemImage: "lock").font(.caption) }
                        if worktree.isPrunable { Label("Directory unavailable", systemImage: "exclamationmark.triangle").font(.caption) }
                    }.padding(18).background(ChromePalette.panelMutedBackground, in: RoundedRectangle(cornerRadius: 10))
                }
            }.padding(28)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func codeBlock(_ text: String) -> some View {
        ScrollView(.horizontal) {
            Text(text).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        }.background(ChromePalette.panelMutedBackground, in: RoundedRectangle(cornerRadius: 8))
    }

    private func emptyState(_ title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openGit(path: String) {
        appModel.openRepository(path: path, name: URL(fileURLWithPath: path).lastPathComponent)
    }
}

private enum WorkbenchPage: String, CaseIterable, Identifiable {
    case sessions = "Sessions"
    case overview = "Overview"
    case tasks = "Tasks"
    case worktrees = "Worktrees"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .sessions: "bubble.left.and.bubble.right"
        case .overview: "square.grid.2x2"
        case .tasks: "checklist"
        case .worktrees: "point.3.connected.trianglepath.dotted"
        }
    }
}

private struct NewWorkbenchTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: WorkbenchModel
    let onCreated: () -> Void
    @State private var title = ""
    @State private var notes = ""
    @State private var agent: WorkbenchAgent = .codex
    @State private var createWorktree = true
    @State private var existingPath = ""
    @State private var newPath: String
    @State private var branch: String

    init(model: WorkbenchModel, onCreated: @escaping () -> Void = {}) {
        self.model = model
        self.onCreated = onCreated
        let suffix = String(UUID().uuidString.prefix(8)).lowercased()
        let repo = URL(fileURLWithPath: model.path)
        _newPath = State(initialValue: repo.deletingLastPathComponent()
            .appendingPathComponent(repo.lastPathComponent + "-worktrees/task-" + suffix).path)
        _branch = State(initialValue: "task/" + suffix)
        _existingPath = State(initialValue: model.path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New Task").font(.title2.bold())
            TextField("Task title", text: $title)
            TextField("Description (optional)", text: $notes, axis: .vertical).lineLimit(3...5)
            Picker("Intended Agent", selection: $agent) {
                ForEach(WorkbenchAgent.allCases) { item in Text(item.rawValue).tag(item) }
            }
            Text("This records your intended Agent. It does not start or connect a session.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Create a dedicated Worktree", isOn: $createWorktree)
            if createWorktree {
                TextField("New branch", text: $branch)
                TextField("Absolute Worktree path", text: $newPath)
            } else {
                Picker("Worktree", selection: $existingPath) {
                    ForEach(model.worktrees.filter { !$0.isBare && !$0.isPrunable }) { worktree in
                        Text(worktree.branchName ?? worktree.path).tag(worktree.path)
                    }
                }
                Text("Changes already present in this directory will appear in the baseline comparison.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = model.error {
                Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create Task") {
                    Task {
                        if await model.createTask(title: title, notes: notes, agent: agent,
                                                  existingPath: createWorktree ? nil : existingPath,
                                                  newPath: newPath, branch: branch) { onCreated(); dismiss() }
                    }
                }.keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSaving
                              || (createWorktree && (branch.isEmpty || !newPath.hasPrefix("/"))))
            }.disabled(model.isSaving)
        }.textFieldStyle(.roundedBorder).padding(28).frame(width: 540)
    }
}
