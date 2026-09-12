import SwiftUI

struct FindBar: View {
    @EnvironmentObject private var session: BrowserSession
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("查找", text: $session.findQuery)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 15))
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(DesignTokens.surfaceSubtle, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .focused($focused)
                .accessibilityIdentifier("find-query-input")
                .onChange(of: session.findQuery) { _, query in
                    session.updateFindQuery(query)
                }

            Text("\(session.findCurrent)/\(session.findTotal)")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(DesignTokens.textSecondary)
                .frame(minWidth: 40)

            Button {
                session.findPrevious()
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 36, height: 36)
            }
            .disabled(session.findTotal == 0)
            .opacity(session.findTotal == 0 ? 0.35 : 1)
            .accessibilityIdentifier("find-previous")

            Button {
                session.findNext()
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 36, height: 36)
            }
            .disabled(session.findTotal == 0)
            .opacity(session.findTotal == 0 ? 0.35 : 1)
            .accessibilityIdentifier("find-next")

            Button {
                session.endFind()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 36, height: 36)
            }
            .accessibilityIdentifier("find-dismiss")
        }
        .foregroundStyle(DesignTokens.textPrimary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(DesignTokens.surfacePanel)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.border)
                .frame(height: 1)
        }
        .onAppear {
            focused = true
        }
        .accessibilityIdentifier("find-bar")
    }
}
