import SwiftUI

/// A friend's photo, or their initials on their avatar colour when they have none.
struct AvatarView: View {
    let profile: FriendProfile
    var size: CGFloat = 40

    private var initials: String {
        String(profile.username.prefix(2)).uppercased()
    }

    private var fill: Color {
        // An empty colour would decode as black; fall back to the accent instead.
        profile.avatarColor.isEmpty ? AppColors.accent : Color(hex: profile.avatarColor)
    }

    var body: some View {
        Group {
            if let url = profile.photoURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            fill
            Text(initials)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}
