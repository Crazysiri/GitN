import SwiftUI

private enum SettingsTab: String, CaseIterable {
    case ai = "AI"
    case git = "Git"
    case editor = "Editor"
    case about = "About"

    var icon: String {
        switch self {
        case .ai:     "sparkles"
        case .git:    "network"
        case .editor: "doc.text"
        case .about:  "info.circle"
        }
    }
}

struct SettingsView: View {
    @State private var activeTab: SettingsTab = .ai

    @State private var aiPrompt: String = AICommitService.userPrompt
    @State private var selectedTool: AICommitTool = AICommitService.selectedTool
    @State private var cursorAPIKey: String = AICommitService.cursorAPIKey
    @State private var promptHasChanges = false
    @State private var toolHasChanges = false
    @State private var keyHasChanges = false
    @State private var toolStatus: AICommitToolStatus?

    @State private var gitlabURL: String = GitLabService.gitlabURL
    @State private var gitlabToken: String = GitLabService.gitlabToken
    @State private var gitlabURLHasChanges = false
    @State private var gitlabTokenHasChanges = false
    @State private var githubToken: String = GitHubService.githubToken
    @State private var githubTokenHasChanges = false

    @State private var maxDiffFileSizeMB: Int = {
        let stored = UserDefaults.standard.integer(forKey: RepoViewModel.maxDiffFileSizeKey)
        return stored > 0 ? stored : RepoViewModel.defaultMaxDiffFileSizeMB
    }()
    @State private var maxDiffSizeHasChanges = false

    var body: some View {
        VStack(spacing: 0) {
            tabBar

            Divider()

            Group {
                switch activeTab {
                case .ai:     aiSettingsTab
                case .git:    gitSettingsTab
                case .editor: editorSettingsTab
                case .about:  aboutTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 520, height: 480)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                tabBarButton(tab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color(.windowBackgroundColor))
    }

    @ViewBuilder
    private func tabBarButton(_ tab: SettingsTab) -> some View {
        let isSelected = activeTab == tab
        Button { activeTab = tab } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 20, weight: .regular))
                    .frame(width: 26, height: 26)
                Text(tab.rawValue)
                    .font(.system(size: 11))
            }
            .frame(width: 68)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    // MARK: - AI Settings

    private var aiSettingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                toolSelectionSection

                Divider()

                // --- Status ---
                agentStatusSection

                if selectedTool.requiresAPIKey {
                    apiKeySection
                    Divider()
                }

                promptSection
            }
            .padding(20)
        }
        .task(id: selectedTool) {
            await refreshToolStatus()
        }
    }

    private var toolSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI Tool")
                .font(.system(size: 13, weight: .semibold))

            Text("Choose which CLI GitN should use when generating commit messages.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Picker("AI Tool", selection: $selectedTool) {
                    ForEach(AICommitTool.allCases) { tool in
                        Text(tool.displayName).tag(tool)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)
                .onChange(of: selectedTool) {
                    toolHasChanges = selectedTool != AICommitService.selectedTool
                }

                Button("Save") {
                    AICommitService.selectedTool = selectedTool
                    toolHasChanges = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!toolHasChanges)
            }
        }
    }

    private var agentStatusSection: some View {
        return VStack(alignment: .leading, spacing: 8) {
            Text(selectedTool.displayName)
                .font(.system(size: 13, weight: .semibold))

            if let toolStatus {
                HStack(spacing: 6) {
                    if toolStatus == .available {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 12))
                        Text("\(selectedTool.displayName) available")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else if toolStatus == .loginRequired {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 12))
                        Text("\(selectedTool.displayName) login required")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.system(size: 12))
                        Text("\(selectedTool.displayName) not found")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                if toolStatus != .available {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(statusInstructionTitle(for: toolStatus))
                            .font(.system(size: 11, weight: .medium))
                        ForEach(statusInstructions(for: toolStatus), id: \.self) { instruction in
                            Text(instruction)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(.controlBackgroundColor))
                    )
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .opacity(0)
                    Text("Checking \(selectedTool.displayName) status...")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @MainActor
    private func refreshToolStatus() async {
        toolStatus = nil
        toolStatus = await AICommitService.toolStatusAsync(selectedTool)
    }

    private func statusInstructionTitle(for status: AICommitToolStatus) -> String {
        switch (selectedTool, status) {
        case (.codex, .loginRequired):
            return "Login to codex in Terminal:"
        case (.codex, .unavailable):
            return "Set up codex:"
        default:
            return "Install \(selectedTool.displayName):"
        }
    }

    private func statusInstructions(for status: AICommitToolStatus) -> [String] {
        switch (selectedTool, status) {
        case (.codex, .loginRequired):
            return [
                "1. Open Terminal",
                "2. Run:  codex",
                "3. Complete the login flow, then return to GitN",
            ]
        default:
            return selectedTool.installInstructions
        }
    }

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("API Key")
                .font(.system(size: 13, weight: .semibold))

            Text("Set your CURSOR_API_KEY. If empty, the app will try to read it from the environment variable.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                SecureField("CURSOR_API_KEY", text: $cursorAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .onChange(of: cursorAPIKey) {
                        keyHasChanges = true
                    }

                Button("Save") {
                    AICommitService.cursorAPIKey = cursorAPIKey
                    keyHasChanges = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!keyHasChanges)

                if !AICommitService.cursorAPIKey.isEmpty {
                    Button(role: .destructive) {
                        cursorAPIKey = ""
                        AICommitService.cursorAPIKey = ""
                        keyHasChanges = false
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .hoverTooltip("Clear saved API key")
                }
            }
        }
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI Commit Prompt")
                .font(.system(size: 13, weight: .semibold))

            Text("Customize the prompt sent to the selected AI tool when generating commit messages.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            TextEditor(text: $aiPrompt)
                .font(.system(size: 11, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 120, maxHeight: 180)
                .background(Color(.textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color(.separatorColor), lineWidth: 1)
                )
                .onChange(of: aiPrompt) {
                    promptHasChanges = true
                }

            HStack {
                Button("Reset to Default") {
                    UserDefaults.standard.removeObject(forKey: "GitN.aiCommitPrompt")
                    aiPrompt = AICommitService.userPrompt
                    promptHasChanges = false
                }
                .controlSize(.small)

                Spacer()

                Button("Save") {
                    AICommitService.userPrompt = aiPrompt
                    promptHasChanges = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!promptHasChanges)
            }
        }
    }

    // MARK: - Git Settings

    private var gitSettingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                gitProviderIntroSection
                Divider()
                gitlabURLSection
                Divider()
                gitlabTokenSection
                Divider()
                githubTokenSection
            }
            .padding(20)
        }
    }

    private var gitProviderIntroSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Code Hosting")
                .font(.system(size: 13, weight: .semibold))

            Text("GitN will detect whether the current repository remote belongs to GitLab or GitHub and show merge or pull requests accordingly.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var gitlabURLSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GitLab")
                .font(.system(size: 13, weight: .semibold))

            Text("Your GitLab instance URL. Leave this as your self-hosted base URL, for example https://gitlab.example.com.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("https://gitlab.example.com", text: $gitlabURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .onChange(of: gitlabURL) {
                        gitlabURLHasChanges = true
                    }

                Button("Save") {
                    GitLabService.gitlabURL = gitlabURL
                    gitlabURLHasChanges = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!gitlabURLHasChanges)

                if !GitLabService.gitlabURL.isEmpty {
                    Button(role: .destructive) {
                        gitlabURL = ""
                        GitLabService.gitlabURL = ""
                        gitlabURLHasChanges = false
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .hoverTooltip("Clear GitLab URL")
                }
            }
        }
    }

    private var gitlabTokenSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Private Token")
                .font(.system(size: 13, weight: .semibold))

            Text("Your GitLab private access token. Create one at GitLab → Preferences → Access Tokens with api scope.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                SecureField("glpat-xxxxxxxxxxxxxxxxxxxx", text: $gitlabToken)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .onChange(of: gitlabToken) {
                        gitlabTokenHasChanges = true
                    }

                Button("Save") {
                    GitLabService.gitlabToken = gitlabToken
                    gitlabTokenHasChanges = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!gitlabTokenHasChanges)

                if !GitLabService.gitlabToken.isEmpty {
                    Button(role: .destructive) {
                        gitlabToken = ""
                        GitLabService.gitlabToken = ""
                        gitlabTokenHasChanges = false
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .hoverTooltip("Clear token")
                }
            }

            // Status indicator
            HStack(spacing: 6) {
                if !GitLabService.gitlabURL.isEmpty && !GitLabService.gitlabToken.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 12))
                    Text("GitLab configured")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .font(.system(size: 12))
                    Text("GitLab not configured — set both URL and token to enable MR features")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        }
    }

    private var githubTokenSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GitHub")
                .font(.system(size: 13, weight: .semibold))

            Text("Only github.com token auth is supported here. Web OAuth button sign-in is not supported.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Link("Create a GitHub personal access token", destination: URL(string: "https://github.com/settings/tokens")!)
                .font(.system(size: 11))

            HStack(spacing: 8) {
                SecureField("github_pat_xxxxxxxxxxxxxxxxxxxx", text: $githubToken)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .onChange(of: githubToken) {
                        githubTokenHasChanges = true
                    }

                Button("Save") {
                    GitHubService.githubToken = githubToken
                    githubTokenHasChanges = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!githubTokenHasChanges)

                if !GitHubService.githubToken.isEmpty {
                    Button(role: .destructive) {
                        githubToken = ""
                        GitHubService.githubToken = ""
                        githubTokenHasChanges = false
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .hoverTooltip("Clear GitHub token")
                }
            }

            HStack(spacing: 6) {
                if GitHubService.isConfigured {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 12))
                    Text("GitHub configured")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .font(.system(size: 12))
                    Text("GitHub not configured — set a token to enable PR features")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Editor Settings

    private var editorSettingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                diffSizeLimitSection
            }
            .padding(20)
        }
    }

    private var diffSizeLimitSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Diff Size Limit")
                .font(.system(size: 13, weight: .semibold))

            Text("Maximum file size for computing diffs. Files larger than this threshold will show a placeholder instead of the full diff to avoid high memory usage.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("", value: $maxDiffFileSizeMB, formatter: NumberFormatter())
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 60)
                    .onChange(of: maxDiffFileSizeMB) {
                        maxDiffSizeHasChanges = true
                    }

                Text("MB")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Stepper("", value: $maxDiffFileSizeMB, in: 1...100)
                    .labelsHidden()
                    .onChange(of: maxDiffFileSizeMB) {
                        maxDiffSizeHasChanges = true
                    }

                Button("Save") {
                    UserDefaults.standard.set(maxDiffFileSizeMB, forKey: RepoViewModel.maxDiffFileSizeKey)
                    maxDiffSizeHasChanges = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!maxDiffSizeHasChanges)

                Button("Reset") {
                    maxDiffFileSizeMB = RepoViewModel.defaultMaxDiffFileSizeMB
                    UserDefaults.standard.removeObject(forKey: RepoViewModel.maxDiffFileSizeKey)
                    maxDiffSizeHasChanges = false
                }
                .controlSize(.small)
                .disabled(maxDiffFileSizeMB == RepoViewModel.defaultMaxDiffFileSizeMB && !maxDiffSizeHasChanges)
            }

            Text("Current limit: \(maxDiffFileSizeMB) MB  ·  Default: \(RepoViewModel.defaultMaxDiffFileSizeMB) MB")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - About

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("GitN")
                .font(.system(size: 20, weight: .bold))

            Text("Version \(appVersion) (\(buildNumber))")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text("A native Git client for macOS")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }

    // MARK: - Version info

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}
