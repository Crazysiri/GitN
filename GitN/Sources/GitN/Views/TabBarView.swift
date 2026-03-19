import SwiftUI
import MarkdownUI

struct TabBarView: View {
    @Environment(AppModel.self) private var appModel

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
            .fixedSize(horizontal: true, vertical: false)

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
    }
}

// MARK: - Features sheet

struct FeaturesView: View {
    let content: String
    @Binding var isPresented: Bool
    @AppStorage("GitN.markdownPreviewScheme") private var scheme: PreviewScheme = .light

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
                Menu {
                    ForEach(PreviewScheme.allCases, id: \.rawValue) { s in
                        Button {
                            scheme = s
                        } label: {
                            HStack {
                                Image(systemName: scheme == s ? "checkmark.circle.fill" : "circle")
                                Text(s.rawValue)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(scheme.swatch)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().strokeBorder(Color.secondary.opacity(0.4), lineWidth: 0.5))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("Preview color scheme")

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
            .background(scheme.background)
            .preferredColorScheme(scheme.colorScheme)
        }
        .frame(minWidth: 680, minHeight: 500)
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
