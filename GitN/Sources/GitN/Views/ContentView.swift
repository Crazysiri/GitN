import SwiftUI

struct ContentView: View {
    private enum ChromeLayout {
        static let tabRowHeight: CGFloat = 47
        static let leadingTrafficLightInset: CGFloat = 86
    }

    @Environment(AppModel.self) private var appModel
    /// 已经加载过的 tab ID 集合（懒加载：点击才加载，加载后不销毁）
    @State private var loadedTabIDs: Set<UUID> = []
    @State private var showFeatures = false
    @State private var isHoveringFeaturesButton = false

    var body: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top
            let contentOffset = max(0, ChromeLayout.tabRowHeight - topInset)

            ZStack(alignment: .top) {
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
                .padding(.top, contentOffset)

                topChromeBar
                    .ignoresSafeArea(.container, edges: .top)
            }
        }
        .frame(minWidth: 1100, minHeight: 700)
        .background(Color(.windowBackgroundColor))
        .navigationTitle("")
        .background(WindowChromeConfigurator())
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

    private var topChromeBar: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: ChromeLayout.leadingTrafficLightInset, height: ChromeLayout.tabRowHeight)

            TabBarView()

            Spacer(minLength: 0)

            Button {
                showFeatures = true
            } label: {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isHoveringFeaturesButton ? ChromePalette.chromeButtonHoverFill : ChromePalette.chromeButtonFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(
                                isHoveringFeaturesButton ? ChromePalette.chromeButtonHoverBorder : ChromePalette.chromeButtonBorder,
                                lineWidth: 1
                            )
                    )
            }
            .buttonStyle(.plain)
            .frame(width: 34, height: 34)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .onHover { isHoveringFeaturesButton = $0 }
            .hoverTooltip("Features")
            .padding(.trailing, 10)
        }
        .frame(height: ChromeLayout.tabRowHeight)
        .background(ChromePalette.navigationBackground)
    }
}

private struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.styleMask.insert(.fullSizeContentView)
        window.toolbar = nil
    }
}
