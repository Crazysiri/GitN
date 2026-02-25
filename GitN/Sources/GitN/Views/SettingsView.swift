import SwiftUI

struct SettingsView: View {
    @State private var aiPrompt: String = AICommitService.userPrompt
    @State private var apiKey: String = AICommitService.apiKey
    @State private var promptHasChanges = false
    @State private var keyHasChanges = false

    @State private var gitlabURL: String = GitLabService.gitlabURL
    @State private var gitlabToken: String = GitLabService.gitlabToken
    @State private var gitlabURLHasChanges = false
    @State private var gitlabTokenHasChanges = false

    var body: some View {
        TabView {
            aiSettingsTab
                .tabItem {
                    Label("AI", systemImage: "sparkles")
                }

            gitlabSettingsTab
                .tabItem {
                    Label("GitLab", systemImage: "network")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 520, height: 480)
    }

    // MARK: - AI Settings

    private var aiSettingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // --- Status ---
                agentStatusSection

                // --- API Key ---
                apiKeySection

                Divider()

                // --- Prompt ---
                promptSection
            }
            .padding(20)
        }
    }

    private var agentStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("cursor-agent")
                .font(.system(size: 13, weight: .semibold))

            HStack(spacing: 6) {
                if AICommitService.isAgentInstalled {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 12))
                    Text("cursor-agent installed")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.system(size: 12))
                    Text("cursor-agent not found")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            if !AICommitService.isAgentInstalled {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Install cursor-agent:")
                        .font(.system(size: 11, weight: .medium))
                    Text("1. Install Cursor IDE from cursor.com")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("2. Run:  cursor-agent install-shell-integration")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("3. Or:   cursor-agent login")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.controlBackgroundColor))
                )
            }
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
                SecureField("CURSOR_API_KEY", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .onChange(of: apiKey) { _ in
                        keyHasChanges = true
                    }

                Button("Save") {
                    AICommitService.apiKey = apiKey
                    keyHasChanges = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!keyHasChanges)

                if !AICommitService.apiKey.isEmpty {
                    Button(role: .destructive) {
                        apiKey = ""
                        AICommitService.apiKey = ""
                        keyHasChanges = false
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Clear saved API key")
                }
            }
        }
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI Commit Prompt")
                .font(.system(size: 13, weight: .semibold))

            Text("Customize the prompt sent to cursor-agent when generating commit messages.")
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
                .onChange(of: aiPrompt) { _ in
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

    // MARK: - GitLab Settings

    private var gitlabSettingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                gitlabURLSection
                Divider()
                gitlabTokenSection
            }
            .padding(20)
        }
    }

    private var gitlabURLSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GitLab URL")
                .font(.system(size: 13, weight: .semibold))

            Text("Your self-hosted GitLab instance URL (e.g. https://gitlab.example.com)")
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
                    .help("Clear GitLab URL")
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
                    .help("Clear token")
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
