import SwiftUI

/// App artwork with a neutral placeholder when metadata is unavailable.
struct AppIconView: View {
    let url: URL?
    var size: CGFloat = 40
    var platform: AppPlatform = .iPhone

    private var cornerRadius: CGFloat { size * 0.2237 }

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url, transaction: Transaction(animation: nil)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(.quaternary, lineWidth: 0.5))
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            Image(systemName: platform.symbolName)
                .font(.system(size: size * 0.42, weight: .regular))
                .foregroundStyle(.secondary)
        }
    }
}
