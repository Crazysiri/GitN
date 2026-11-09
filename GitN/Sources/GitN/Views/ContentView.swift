import SwiftUI

struct ContentView: View {
    private enum ChromeLayout {
        /// Minimal system titlebar row — just enough for traffic lights
        static let titlebarHeight: CGFloat = 25
        /// Tab row below the titlebar
        static let tabRowHeight: CGFloat = 43
        /// Total top chrome height (titlebar + tab row)
        static let totalChromeHeight: CGFloat = titlebarHeight + tabRowHeight
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
            let contentOffset = max(0, ChromeLayout.totalChromeHeight - topInset)

            ZStack(alignment: .top) {
                ZStack {
                    // 仅渲染已加载过的 tab（懒加载），加载后通过 opacity 缓存不销毁
                    ForEach(appModel.tabs.filter { shouldRender($0) }) { tab in
                        let isActive = !appModel.showNewTab && appModel.selectedTabID == tab.id
                        Group {
                            if tab.kind == .workbench {
                                WorkbenchView(tab: tab, isActive: isActive)
                            } else {
                                RepoContainerView(tab: tab, isActive: isActive)
                            }
                        }
                            .opacity(isActive ? 1 : 0)
                            .disabled(!isActive)
                            .allowsHitTesting(isActive)
                            .zIndex(isActive ? 1 : 0)
                    }

                    if appModel.showNewTab || appModel.selectedTab == nil {
                        NewTabView()
                    }
                }
                .padding(.top, contentOffset)

                topChromeArea
                    .ignoresSafeArea(.container, edges: .top)
            }
        }
        .frame(minWidth: 1100, minHeight: 700)
        .background(Color(.windowBackgroundColor))
        .navigationTitle("")
        .background(WindowChromeConfigurator())
        .sheet(isPresented: $showFeatures) {
            if let url = GitNResources.featuresURL,
               let content = try? String(contentsOf: url, encoding: .utf8) {
                FeaturesView(content: content, isPresented: $showFeatures)
            } else {
                Text("FEATURES.md not found.")
                    .padding(24)
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
        .onChange(of: appModel.tabs.map(\.id)) { _, ids in
            loadedTabIDs.formIntersection(Set(ids))
        }
    }

    /// 判断一个 tab 是否需要渲染：已加载过 OR 当前正被选中
    private func shouldRender(_ tab: RepoTab) -> Bool {
        loadedTabIDs.contains(tab.id)
            || (!appModel.showNewTab && tab.id == appModel.selectedTabID)
    }

    /// Top chrome area: a minimal titlebar row (draggable, for traffic lights) + a separate tab row below
    private var topChromeArea: some View {
        VStack(spacing: 0) {
            // Row 1: Minimal system titlebar — traffic lights live here, window draggable
            titlebarRow

            // Row 2: Tab bar — NOT in the titlebar, so no window drag interference
            tabRow
        }
    }

    /// Minimal titlebar row: traffic light area, window draggable
    private var titlebarRow: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
        }
        .frame(height: ChromeLayout.titlebarHeight)
        .background(ChromePalette.navigationBackground)
    }

    /// Tab row: sits below the titlebar, separate from the system chrome
    private var tabRow: some View {
        HStack(spacing: 0) {
            TabBarView()

            Spacer(minLength: 0)

            Button {
                showFeatures = true
            } label: {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
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
