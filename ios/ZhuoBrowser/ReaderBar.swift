import SwiftUI

struct ReaderBar: View {
    @EnvironmentObject private var session: BrowserSession

    var body: some View {
        let theme = ReaderTheme.theme(for: session.readerSettings.paper)
        HStack(spacing: 8) {
            Button("A−") {
                session.readerSettings.shrink()
                session.refreshReader()
            }
            .disabled(!session.readerSettings.canShrink)
            .opacity(session.readerSettings.canShrink ? 1 : 0.35)
            .accessibilityIdentifier("reader-shrink")

            Button("A+") {
                session.readerSettings.grow()
                session.refreshReader()
            }
            .font(.system(size: 16, weight: .medium))
            .disabled(!session.readerSettings.canGrow)
            .opacity(session.readerSettings.canGrow ? 1 : 0.35)
            .accessibilityIdentifier("reader-grow")

            Button("行距") {
                session.readerSettings.cycleLineHeight()
                session.refreshReader()
            }
            .font(.system(size: 12))
            .accessibilityIdentifier("reader-line-height")

            HStack(spacing: 6) {
                ForEach(ReaderPaper.allCases, id: \.rawValue) { paper in
                    Button {
                        session.readerSettings.paper = paper
                        session.refreshReader()
                    } label: {
                        Circle()
                            .fill(Color(hex: ReaderTheme.theme(for: paper).background))
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle().stroke(
                                    session.readerSettings.paper == paper ? Color(hex: theme.accent) : Color(hex: theme.pillBorder),
                                    lineWidth: session.readerSettings.paper == paper ? 2 : 1
                                )
                            )
                    }
                    .accessibilityIdentifier("reader-paper-\(paper.rawValue)")
                }
            }

            Spacer()

            Button("完成") {
                session.toggleReader()
            }
            .font(.system(size: 15, weight: .medium))
            .accessibilityIdentifier("reader-done")
        }
        .font(.system(size: 13))
        .foregroundStyle(Color(hex: theme.textPrimary))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(hex: theme.background))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(hex: theme.border))
                .frame(height: 1)
        }
        .accessibilityIdentifier("reader-bar")
    }
}
