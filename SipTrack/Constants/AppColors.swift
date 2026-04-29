import SwiftUI

enum AppColors {
    static let background      = Color(hex: "#0A0A0F")
    static let surface         = Color(hex: "#141420")
    static let surfaceTop      = Color(hex: "#1C1C2E")   // gradient card top
    static let surfaceBottom   = Color(hex: "#0D0D17")   // gradient card bottom
    static let surfaceElevated = Color(hex: "#1C1C2E")
    static let card            = Color(hex: "#1A1A2A")
    static let border          = Color(hex: "#2A2A3A")
    static let rimLight        = Color.white.opacity(0.09)   // top-edge glass highlight
    static let text            = Color(hex: "#F5F5F7")
    static let textWarm        = Color(hex: "#D8CAAA")       // warm off-white for headings
    static let textSecondary   = Color(hex: "#8E8E9A")
    static let textTertiary    = Color(hex: "#5A5A6A")
    static let accent          = Color(hex: "#F0A830")
    static let accentWarm      = Color(hex: "#FFD166")       // lighter gold for gradients
    static let accentDim       = Color(hex: "#F0A830").opacity(0.15)
    static let accentGlow      = Color(hex: "#F0A830").opacity(0.3)
    static let danger          = Color(hex: "#FF4757")
    static let dangerDim       = Color(hex: "#FF4757").opacity(0.15)
    static let success         = Color(hex: "#2ED573")
    static let successDim      = Color(hex: "#2ED573").opacity(0.15)
    static let water           = Color(hex: "#40AAFF")
    static let waterDim        = Color(hex: "#40AAFF").opacity(0.15)
    static let overlay         = Color.black.opacity(0.6)
}

// MARK: - Premium card modifier

extension View {
    /// Replaces flat surface+border with a gradient background and glass-rim border.
    /// Drop-in replacement for: .background(AppColors.surface).cornerRadius(r).overlay(…)
    func premiumCard(
        radius: CGFloat = 16,
        tint: Color = .clear,
        tintOpacity: Double = 0,
        borderTop: Color = AppColors.rimLight,
        borderBottom: Color = AppColors.border
    ) -> some View {
        self
            .background(
                ZStack {
                    LinearGradient(
                        colors: [AppColors.surfaceTop, AppColors.surfaceBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    if tintOpacity > 0 { tint.opacity(tintOpacity) }
                }
            )
            .cornerRadius(radius)
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(
                        LinearGradient(
                            colors: [borderTop, borderBottom.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
                  red:     Double(r) / 255,
                  green:   Double(g) / 255,
                  blue:    Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}
