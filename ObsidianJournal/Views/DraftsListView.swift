import SwiftUI

struct DraftsListView: View {
    @ObservedObject var draftManager: DraftManager
    var onSelectDraft: (Draft) -> Void
    var onCreateDraft: () -> Void

    private var sortedDrafts: [Draft] {
        draftManager.activeDrafts.sorted(by: { $0.modifiedAt > $1.modifiedAt })
    }

    var body: some View {
        List {
            // Filter explicitly for .draft status
            ForEach(sortedDrafts) { draft in
                Button(action: {
                    onSelectDraft(draft)
                }) {
                    DraftSidebarRow(
                        draft: draft,
                        isSelected: draftManager.currentDraft?.id == draft.id
                    )
                }
                .buttonStyle(.plain)
            }
            .onDelete { indexSet in
                indexSet.forEach { index in
                    draftManager.deleteDraft(sortedDrafts[index])
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: onCreateDraft) {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New Draft")
            }
        }
    }
}

private struct DraftSidebarRow: View {
    let draft: Draft
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "doc.text.fill" : "doc.text")
                .foregroundStyle(isSelected ? ThemeManager.obsidianPurple : .secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(draft.content.isEmpty ? "Empty Draft" : draft.content)
                    .lineLimit(1)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(draft.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
