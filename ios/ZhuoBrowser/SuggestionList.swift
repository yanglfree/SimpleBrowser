import SwiftUI

struct SuggestionList: View {
    let suggestions: [AddressSuggestion]
    let onSelect: (AddressSuggestion) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(suggestions) { item in
                    Button {
                        onSelect(item)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: icon(for: item.kind))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(DesignTokens.accent)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .foregroundStyle(DesignTokens.textPrimary)
                                    .lineLimit(1)
                                if !item.subtitle.isEmpty {
                                    Text(item.subtitle)
                                        .font(.system(size: 12))
                                        .foregroundStyle(DesignTokens.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("suggestion-\(item.id)")
                }
            }
        }
        .background(DesignTokens.surfacePanel)
        .accessibilityIdentifier("suggestion-list")
    }

    private func icon(for kind: SuggestionKind) -> String {
        switch kind {
        case .history: return "clock"
        case .bookmark: return "bookmark"
        case .search: return "magnifyingglass"
        }
    }
}
