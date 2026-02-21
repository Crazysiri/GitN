import SwiftUI

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
                            onSelect: { appModel.selectedTabID = tab.id },
                            onClose: { appModel.closeTab(tab.id) }
                        )
                    }
                }
                .padding(.horizontal, 4)
            }

            Spacer()

            Button(action: { appModel.openRepository() }) {
                Image(systemName: "plus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
        }
        .frame(height: 36)
        .background(Color(.controlBackgroundColor))
    }
}

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
