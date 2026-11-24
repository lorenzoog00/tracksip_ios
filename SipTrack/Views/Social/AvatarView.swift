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

/// Who a row is: the display name over "@username" when one is set, otherwise
/// "@username" alone. Names aren't unique, so the username always shows with
/// one: it's what tells two people with the same name apart.
struct ProfileNameLabel: View {
    let profile: FriendProfile
    /// The top line's size; "@username" under a name is a step smaller.
    var size: CGFloat = 16
    /// The weight of "@username" when it shows alone.
    var usernameWeight: Font.Weight = .medium

    var body: some View {
        if let name = profile.name {
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(AppColors.text)
                Text("@\(profile.username)")
                    .font(.system(size: size - 3))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .lineLimit(1)
            .accessibilityElement(children: .combine)
        } else {
            Text("@\(profile.username)")
                .font(.system(size: size, weight: usernameWeight))
                .foregroundStyle(AppColors.text)
        }
    }
}
