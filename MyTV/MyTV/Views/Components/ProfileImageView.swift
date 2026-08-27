import SwiftUI

public struct ProfileImageView: View {
    @ObservedObject private var storage = StorageManager.shared
    public var size: CGFloat = 34

    public init(size: CGFloat = 34) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.2, green: 0.45, blue: 0.95),
                            Color(red: 0.55, green: 0.25, blue: 0.85)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                )

            if let active = storage.activeAccount, !active.name.isEmpty {
                let initial = String(active.name.prefix(1)).uppercased()
                Text(initial)
                    .font(.system(size: size * 0.44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.44, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
    }
}
