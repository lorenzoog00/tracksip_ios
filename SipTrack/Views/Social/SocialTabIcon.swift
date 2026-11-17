import SwiftUI
import UIKit

/// Shows a notice for a social-screen failure that has no inline spot.
func showSocialNotice(title: String, message: String) {
    NoticeCenter.shared.show(Notice(
        icon: "exclamationmark.triangle.fill",
        tone: .danger,
        title: title,
        message: message,
        actions: [NoticeAction("OK") {}]
    ))
}

/// Tab items are flattened to a template image, which drops any SwiftUI overlay.
/// To show the live dot we pre-render the icon with the dot baked in and mark it
/// `.alwaysOriginal`, tinting it ourselves for the selected/unselected state.
enum SocialTabIcon {
    @ViewBuilder
    static func image(showDot: Bool, selected: Bool) -> some View {
        if showDot {
            Image(uiImage: render(selected: selected))
        } else {
            Image(systemName: "person.2.fill")
        }
    }

    private static func render(selected: Bool) -> UIImage {
        let tint = selected ? UIColor(AppColors.accent) : UIColor(AppColors.textSecondary)
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        let symbol = UIImage(systemName: "person.2.fill", withConfiguration: config)?
            .withTintColor(tint, renderingMode: .alwaysOriginal) ?? UIImage()
        let dot: CGFloat = 8
        let size = CGSize(width: symbol.size.width + 4, height: symbol.size.height + 2)
        let rendered = UIGraphicsImageRenderer(size: size).image { _ in
            symbol.draw(at: CGPoint(x: 0, y: 2))
            UIColor(AppColors.success).setFill()
            UIBezierPath(ovalIn: CGRect(x: size.width - dot, y: 0, width: dot, height: dot)).fill()
        }
        return rendered.withRenderingMode(.alwaysOriginal)
    }
}
