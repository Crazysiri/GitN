import SwiftUI

struct NewTabView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        HStack(spacing: 0) {
            // 左侧：Repositories 区域
            VStack(alignment: .leading, spacing: 20) {
                Text("Repositories")
                    .font(.system(size: 32, weight: .bold))
                    .padding(.top, 40)
                    .padding(.leading, 40)

                // Open, Clone, Create 按钮（只保留 Open）
                HStack(spacing: 16) {
                    Button(action: {
                        appModel.openRepository()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                            Text("Open")
                        }
                        .frame(width: 120, height: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding(.leading, 40)

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
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(appModel.recentRepos, id: \.path) { repo in
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
                                .padding(.horizontal, 40)
                            }
                        }
                        .padding(.top, 8)
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
