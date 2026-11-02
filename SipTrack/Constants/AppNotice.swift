import SwiftUI

// A replacement for `.alert` and `.confirmationDialog`.
//
// The system versions are grey, square, system-font boxes that land on top of a
// dark gold-accented app and look like they belong to a different product. They
// also have a second cost that is easy to miss: each one is a presented UIKit
// controller, so a button inside one cannot open another sheet until it has
// finished dismissing. That is what broke account deletion — the Google
// re-authentication sheet had nowhere to go. A notice drawn inside SwiftUI
// presents nothing, so that whole class of bug disappears with it.
//
// Everything is centred in `NoticeCenter` and hosted once in `RootView`, above
// the navigation stack, so a notice covers the navigation bar instead of
// leaving it floating over the dimmed backdrop.

// MARK: - Model

struct NoticeAction: Identifiable {
    enum Kind {
        /// Gold, filled. One per notice.
        case primary
        /// Red, outlined. For anything that destroys something.
        case destructive
        /// Text only. The way out.
        case quiet
    }

    let id = UUID()
    let title: String
    let kind: Kind
    /// Receives what was typed into the notice's field, or "" when it has none.
    let handler: (String) -> Void

    init(_ title: String, kind: Kind = .primary, handler: @escaping () -> Void = {}) {
        self.title = title
        self.kind = kind
        self.handler = { _ in handler() }
    }

    init(_ title: String, kind: Kind = .primary, input handler: @escaping (String) -> Void) {
        self.title = title
        self.kind = kind
        self.handler = handler
    }
}

struct NoticeField {
    let placeholder: String
    let isSecure: Bool

    init(placeholder: String, isSecure: Bool = true) {
        self.placeholder = placeholder
        self.isSecure = isSecure
    }
}

struct Notice: Identifiable {
    enum Tone {
        case accent, danger, water, success

        var color: Color {
            switch self {
            case .accent:  AppColors.accent
            case .danger:  AppColors.danger
            case .water:   AppColors.water
            case .success: AppColors.success
            }
        }
    }

    let id = UUID()
    let icon: String
    let tone: Tone
    let title: String
    let message: String?
    let actions: [NoticeAction]
    let field: NoticeField?

    init(
        icon: String,
        tone: Tone = .accent,
        title: String,
        message: String? = nil,
        field: NoticeField? = nil,
        actions: [NoticeAction]
    ) {
        self.icon = icon
        self.tone = tone
        self.title = title
        self.message = message
        self.field = field
        self.actions = actions
    }
}

// MARK: - Centre

@MainActor
final class NoticeCenter: ObservableObject {
    static let shared = NoticeCenter()
    private init() {}

    @Published private(set) var current: Notice?

    func show(_ notice: Notice) {
        current = notice
    }

    func dismiss() {
        current = nil
    }
}

// MARK: - Host

extension View {
    /// Hosts notices above everything. Applied once, in `RootView`.
    func noticeHost() -> some View {
        modifier(NoticeHost())
    }
}

private struct NoticeHost: ViewModifier {
    @ObservedObject private var center = NoticeCenter.shared

    func body(content: Content) -> some View {
        content
            .overlay {
                if let notice = center.current {
                    NoticeOverlay(notice: notice)
                        // A new id per notice restarts the field and the
                        // entrance animation when one replaces another.
                        .id(notice.id)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.18), value: center.current?.id)
    }
}

private struct NoticeOverlay: View {
    let notice: Notice

    @State private var fieldText = ""
    @State private var shown = false
    @FocusState private var fieldFocused: Bool

    /// The way out, if the notice offers one. A backdrop tap uses it, so a
    /// notice with no quiet action cannot be dismissed by accident.
    private var escape: NoticeAction? {
        notice.actions.last { $0.kind == .quiet }
    }

    var body: some View {
        ZStack {
            AppColors.overlay
                .ignoresSafeArea()
                .onTapGesture { if let escape { run(escape) } }

            card
                .scaleEffect(shown ? 1 : 0.94)
                .opacity(shown ? 1 : 0)
                .padding(.horizontal, 32)
        }
        .accessibilityAddTraits(.isModal)
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { shown = true }
            if notice.field != nil { fieldFocused = true }
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(notice.tone.color.opacity(0.12))
                    .frame(width: 60, height: 60)
                Image(systemName: notice.icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(notice.tone.color)
            }
            .padding(.top, 26)

            Text(notice.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(AppColors.text)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
                .padding(.horizontal, 24)

            if let message = notice.message {
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.top, 8)
                    .padding(.horizontal, 24)
            }

            if let field = notice.field {
                Group {
                    if field.isSecure {
                        SecureField(field.placeholder, text: $fieldText)
                    } else {
                        TextField(field.placeholder, text: $fieldText)
                    }
                }
                .textContentType(field.isSecure ? .password : .none)
                .focused($fieldFocused)
                .submitLabel(.go)
                .onSubmit { if let first = notice.actions.first(where: { $0.kind != .quiet }) { run(first) } }
                .padding(13)
                .background(AppColors.surface)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
                .foregroundStyle(AppColors.text)
                .padding(.top, 18)
                .padding(.horizontal, 20)
            }

            VStack(spacing: 10) {
                ForEach(notice.actions) { action in
                    button(for: action)
                }
            }
            .padding(.top, 22)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: 340)
        .premiumCard(radius: 22)
        .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
    }

    @ViewBuilder
    private func button(for action: NoticeAction) -> some View {
        switch action.kind {
        case .primary:
            Button { run(action) } label: {
                Text(action.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        LinearGradient(
                            colors: [AppColors.accentWarm, AppColors.accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(14)
            }
            .buttonStyle(.plain)

        case .destructive:
            Button { run(action) } label: {
                Text(action.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.danger)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(AppColors.dangerDim)
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(AppColors.danger.opacity(0.45), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

        case .quiet:
            Button { run(action) } label: {
                Text(action.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
    }

    /// Dismisses first so the notice is gone before the handler opens anything
    /// of its own — the ordering that the old confirmation dialog got wrong.
    private func run(_ action: NoticeAction) {
        let text = fieldText
        fieldFocused = false
        NoticeCenter.shared.dismiss()
        action.handler(text)
    }
}
