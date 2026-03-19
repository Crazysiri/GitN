import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    /// 已经加载过的 tab ID 集合（懒加载：点击才加载，加载后不销毁）
    @State private var loadedTabIDs: Set<UUID> = []
    @State private var showFeatures = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // 仅渲染已加载过的 tab（懒加载），加载后通过 opacity 缓存不销毁
                ForEach(appModel.tabs.filter { shouldRender($0) }) { tab in
                    let isActive = !appModel.showNewTab && appModel.selectedTabID == tab.id
                    RepoContainerView(tab: tab, isActive: isActive)
                        .opacity(isActive ? 1 : 0)
                        .allowsHitTesting(isActive)
                        .zIndex(isActive ? 1 : 0)
                }

                if appModel.showNewTab || appModel.selectedTab == nil {
                    NewTabView()
                }
            }
        }
        .frame(minWidth: 1100, minHeight: 700)
        .background(Color(.windowBackgroundColor))
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                TabBarView()
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showFeatures = true
                } label: {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 11, weight: .medium))
                }
                .help("Features")
            }
        }
        .sheet(isPresented: $showFeatures) {
            if let url = Bundle.module.url(forResource: "FEATURES", withExtension: "md"),
               let content = try? String(contentsOf: url, encoding: .utf8) {
                FeaturesView(content: content, isPresented: $showFeatures)
            }
        }
        .onAppear {
            // 启动时仅激活当前选中的 tab
            if let id = appModel.selectedTabID {
                loadedTabIDs.insert(id)
            }
        }
        .onChange(of: appModel.selectedTabID) { _, newID in
            // 点击 tab 时将其加入已加载集合
            if let id = newID {
                loadedTabIDs.insert(id)
            }
        }
    }

    /// 判断一个 tab 是否需要渲染：已加载过 OR 当前正被选中
    private func shouldRender(_ tab: RepoTab) -> Bool {
        loadedTabIDs.contains(tab.id)
            || (!appModel.showNewTab && tab.id == appModel.selectedTabID)
    }
}
