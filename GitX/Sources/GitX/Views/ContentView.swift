import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(spacing: 0) {
            TabBarView()
            Divider()

            if let tab = appModel.selectedTab {
                RepoContainerView(tab: tab)
                    .id(tab.id)
            } else {
                WelcomeView()
            }
        }
        .frame(minWidth: 1100, minHeight: 700)
        .background(Color(.windowBackgroundColor))
    }
}

struct WelcomeView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("GitX")
                .font(.largeTitle.bold())
            Text("Open a repository to get started")
                .foregroundStyle(.secondary)
            Button("Open Repository...") {
                appModel.openRepository()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
