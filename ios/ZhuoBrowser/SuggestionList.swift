import SwiftUI

struct SuggestionList: View {
    let suggestions: [AddressSuggestion]
    let onSelect: (AddressSuggestion) -> Void
    let onComplete: (AddressSuggestion) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 0) {
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
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("suggestion-\(item.id)")

                        if index == 0 {
                            Button {
                                onComplete(item)
                            } label: {
                                Image(systemName: "arrow.up.left")
                                    .frame(width: 36, height: 36)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("补全为 \(item.url)")
                            .accessibilityIdentifier("suggestion-complete")
                        }
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 8)
                    .padding(.vertical, 12)
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
