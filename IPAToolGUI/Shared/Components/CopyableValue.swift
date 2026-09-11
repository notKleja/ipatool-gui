import SwiftUI

/// Label/value row whose value can be copied via a context menu or an inline button.
struct CopyableValue: View {
    let label: String
    let value: String
    var monospaced = false

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                Text(value)
                    .font(monospaced ? .body.monospaced() : .body)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button {
                    Pasteboard.copy(value)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Copy \(label)")
                .accessibilityLabel("Copy \(label)")
            }
        }
        .contextMenu {
            Button("Copy \(label)") { Pasteboard.copy(value) }
        }
    }
}
