import SwiftUI
import AppKit
import MarkdownUI

struct TabBarView: View {
    @Environment(AppModel.self) private var appModel
    @State private var windowWidth: CGFloat = 1100
    @State private var hostingWindow: NSWindow? = nil

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(appModel.tabs) { tab in
                        TabItemView(
                            tab: tab,
                            isSelected: tab.id == appModel.selectedTabID,
                            onSelect: {
                                appModel.selectedTabID = tab.id
                                appModel.showNewTab = false
                            },
                            onClose: { appModel.closeTab(tab.id) }
                        )
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(maxWidth: windowWidth * 0.65)

            Divider()
                .frame(height: 14)
                .padding(.horizontal, 6)

            Button(action: { appModel.showNewTabView() }) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Color(.controlColor), in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 4)
        }
        .padding(.horizontal, 10)
        .background(
            HostingWindowAccessor { window in
                guard hostingWindow == nil, let window else { return }
                hostingWindow = window
                windowWidth = window.frame.width
            }
        )
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { notification in
            guard let window = notification.object as? NSWindow,
                  window === hostingWindow else { return }
            windowWidth = window.frame.width
            print("[TabBarView] didResize windowWidth=\(windowWidth)")
        }
    }
}

/// 通过 NSViewRepresentable 拿到当前 SwiftUI 视图的宿主 NSWindow
private struct HostingWindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onWindow(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onWindow(nsView.window) }
    }
}

// MARK: - Features sheet

struct FeaturesView: View {
    @Environment(ThemeManager.self) private var theme
    let content: String
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text("FEATURES.md")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.windowBackgroundColor))

            Divider()

            ScrollView {
                Markdown(content)
                    .markdownTheme(.gitHub)
                    .textSelection(.enabled)
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 680, minHeight: 500)
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }
}

// MARK: -

struct TabItemView: View {
    let tab: RepoTab
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .font(.caption2)
                .foregroundStyle(isSelected ? .primary : .secondary)

            Text(tab.name)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(isSelected ? .primary : .secondary)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovering || isSelected ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color(.selectedContentBackgroundColor).opacity(0.3) : Color.clear)
        )
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
    }
}
