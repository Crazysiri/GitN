import SwiftUI

struct WorkbenchSessionsView: View {
    @Bindable var model: WorkbenchModel
    let openGit: (String) -> Void
    let openTask: () -> Void
    @State private var showSetup = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sessions").font(.headline)
                Spacer()
                Toggle("Include unassociated", isOn: $model.includeUnassociatedSessions).toggleStyle(.checkbox)
                    .font(.system(size: 11))
                Button(model.isDiscovering ? "Reading…" : "Discover Codex") { Task { await model.discoverCodex() } }
                    .disabled(model.isDiscovering || model.isLoading)
                Button("Connect Hooks…") { showSetup = true }
            }.padding(14)
            if let message = model.discoveryMessage {
                Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.bottom, 10)
            }
            Divider()
            HSplitView {
                VStack(spacing: 0) {
                    if model.sessions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Work in Codex or Kiro first").font(.headline)
                            Text("Discover existing Codex conversations or connect Hooks for new Codex / Kiro activity. You can associate a Worktree later.")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }.padding(20)
                        Spacer()
                    } else {
                        List(selection: $model.selectedSessionID) {
                            ForEach(model.sessions) { session in
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(session.displayTitle).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                                    Text(session.agent.rawValue + " · " + (session.worktrees.isEmpty ? "Unassociated" : "\(session.worktrees.count) directory link(s)"))
                                        .font(.system(size: 11)).foregroundStyle(.secondary)
                                }.padding(.vertical, 7).tag(session.id)
                            }
                        }.listStyle(.sidebar)
                    }
                }.frame(minWidth: 220, idealWidth: 270, maxWidth: 360)
                if let session = model.selectedSession {
                    detail(session).frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sessions before tasks").font(.title2.weight(.semibold))
                        Text("No task or directory choice is required to start. Multiple sessions can share a Worktree; group them when you are ready.")
                            .foregroundStyle(.secondary)
                    }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onChange(of: model.includeUnassociatedSessions) { _, _ in Task { await model.refreshSessions() } }
        .sheet(isPresented: $showSetup) { SessionHookSetupView(setup: model.hookSetup) }
    }

    private func detail(_ session: WorkbenchSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(session.displayTitle).font(.system(size: 22, weight: .semibold)).textSelection(.enabled)
                Text("\(session.agent.rawValue) · \(session.externalID)")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                Text(session.externalTitle == nil ? "Fallback name — no external title available." : "Title provided by \(session.agent.rawValue).")
                    .font(.caption).foregroundStyle(.secondary)
                if let event = session.lastEvent {
                    Text("Last reported event: \(event)").font(.system(size: 12))
                }
                Text("Last observed \(session.lastObservedAt.formatted()) · Activity is not a live process status")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                HStack {
                    Text("Directory Associations").font(.headline)
                    Spacer()
                    Menu("Associate Worktree") {
                        ForEach(model.worktrees.filter { !$0.isBare && !$0.isPrunable }) { worktree in
                            Button(worktree.branchName ?? worktree.path) { Task { await model.associateSession(session, worktree: worktree) } }
                        }
                    }
                }
                if session.worktrees.isEmpty {
                    Text("Not associated yet. Continue in your AI tool, or choose an existing Worktree here when the target is known.")
                        .foregroundStyle(.secondary)
                }
                if let cwd = session.reportedCWD {
                    Text("Reported directory: \(cwd)").font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                }
                ForEach(session.worktrees) { association in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(URL(fileURLWithPath: association.path).lastPathComponent).fontWeight(.medium)
                            Spacer()
                            Button("Open in Git") { openGit(association.path) }
                                .disabled(!FileManager.default.fileExists(atPath: association.path))
                        }
                        Text(association.path).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                        Text(association.source == .manual ? "Manually associated" : "Observed session directory")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("\(association.firstObservedAt.formatted()) – \(association.lastObservedAt.formatted())")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(12).background(ChromePalette.panelMutedBackground, in: RoundedRectangle(cornerRadius: 8))
                }
                Text("Directory history does not establish exclusive ownership or attribute individual code edits.")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                HStack {
                    Text("Tasks").font(.headline)
                    Spacer()
                    Menu("Add to Task") {
                        ForEach(model.tasks) { task in
                            Button(task.title) { Task { await model.addSession(session, to: task) } }
                                .disabled(model.tasks(for: session).contains { $0.id == task.id })
                        }
                    }.disabled(model.tasks.isEmpty)
                    Button("Create Task from Session") {
                        Task { if await model.createTask(from: session) { openTask() } }
                    }
                }
                ForEach(model.tasks(for: session)) { task in
                    Button {
                        model.selectedTaskID = task.id
                        openTask()
                    } label: { Label(task.title, systemImage: "checklist") }
                }
                Text("A task is optional. Starting-commit comparisons begin when you group or associate directories in GitN.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }
    }
}

private struct SessionHookSetupView: View {
    let setup: SessionHookSetup
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?
    @State private var revision = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Connect Session Hooks").font(.title2.bold())
            Text("These project hooks report session IDs, working directories and event names to a local inbox, including while GitN is closed. Prompts, tool arguments and transcripts are discarded. GitN reads the inbox when the workbench is active.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            ForEach(WorkbenchAgent.allCases) { agent in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(agent.rawValue).font(.headline)
                        Text(setup.isInstalled(agent) ? "Configured" : "Not configured").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Install / Repair") { perform { try setup.install(agent) } }
                        Button("Remove Hooks") { perform { try setup.uninstall(agent) } }
                            .disabled(!setup.isInstalled(agent))
                    }
                    Text(setup.configurationURL(agent).path).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                    Text(agent == .codex
                         ? "Review and trust these hooks in Codex with /hooks. Existing hooks are preserved."
                         : "For current Kiro IDE / CLI V3 hook format. Older CLI versions require an upgrade. Session titles may be unavailable.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(12).background(ChromePalette.panelMutedBackground, in: RoundedRectangle(cornerRadius: 8))
            }
            Text("Helper: \(setup.installedRelay.path)").font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
            if let message { Text(message).font(.caption).textSelection(.enabled) }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 640).id(revision)
    }
    private func perform(_ action: () throws -> Void) {
        do { try action(); message = "Configuration updated. Restart or reload the AI tool to apply it." }
        catch { message = error.localizedDescription }
        revision += 1
    }
}
