import SwiftUI

struct EmptyStateView<Actions: View>: View {
    let title: String
    let message: String
    var systemImage: String
    @ViewBuilder var actions: () -> Actions

    init(_ title: String, message: String, systemImage: String, @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actions = actions
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            actions()
        }
    }
}
