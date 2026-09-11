import SwiftUI

/// Presents an `EngineError` as a native alert with an optional "Show Details" sheet.
struct EngineErrorAlertModifier: ViewModifier {
    @Binding var error: EngineError?
    @State private var detailError: EngineError?

    func body(content: Content) -> some View {
        content
            .alert(error?.kind.title ?? "Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) { error = nil }
                if let error, !error.detailText.isEmpty {
                    Button("Show Details") { detailError = error }
                }
            } message: {
                Text(error?.kind.message ?? "")
            }
            .sheet(item: $detailError) { error in
                ErrorDetailsView(error: error)
            }
    }
}

extension EngineError: Identifiable {
    var id: String { "\(kind.rawValue)-\(rawMessage)-\(diagnostics ?? "")" }
}

extension View {
    func engineErrorAlert(_ error: Binding<EngineError?>) -> some View {
        modifier(EngineErrorAlertModifier(error: error))
    }
}

struct ErrorDetailsView: View {
    let error: EngineError
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(error.kind.title).font(.headline)
            Text(error.kind.message).foregroundStyle(.secondary)
            ScrollView {
                Text(error.detailText.isEmpty ? "No additional details." : error.detailText)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Button("Copy Details") { Pasteboard.copy(error.detailText) }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 480, idealWidth: 560, minHeight: 300)
    }
}
