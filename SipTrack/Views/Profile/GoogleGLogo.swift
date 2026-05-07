import SwiftUI

struct GoogleGLogo: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let cx = w / 2
            let cy = h / 2
            let r  = min(w, h) / 2

            // Blue segment (right, wraps top)
            var blue = Path()
            blue.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                        startAngle: .degrees(-23), endAngle: .degrees(90), clockwise: false)
            blue.addLine(to: CGPoint(x: cx, y: cy))
            ctx.fill(blue, with: .color(Color(red: 0.26, green: 0.52, blue: 0.96)))

            // Green segment (bottom right)
            var green = Path()
            green.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                         startAngle: .degrees(90), endAngle: .degrees(195), clockwise: false)
            green.addLine(to: CGPoint(x: cx, y: cy))
            ctx.fill(green, with: .color(Color(red: 0.20, green: 0.66, blue: 0.33)))

            // Yellow segment (bottom left)
            var yellow = Path()
            yellow.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                          startAngle: .degrees(195), endAngle: .degrees(240), clockwise: false)
            yellow.addLine(to: CGPoint(x: cx, y: cy))
            ctx.fill(yellow, with: .color(Color(red: 1.0, green: 0.74, blue: 0.0)))

            // Red segment (left, top)
            var red = Path()
            red.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                       startAngle: .degrees(240), endAngle: .degrees(337), clockwise: false)
            red.addLine(to: CGPoint(x: cx, y: cy))
            ctx.fill(red, with: .color(Color(red: 0.92, green: 0.26, blue: 0.21)))

            // White inner circle
            let innerR = r * 0.62
            var inner = Path()
            inner.addEllipse(in: CGRect(x: cx - innerR, y: cy - innerR,
                                        width: innerR * 2, height: innerR * 2))
            ctx.fill(inner, with: .color(.white))

            // Blue horizontal bar (the crossbar of the G)
            let barLeft   = cx
            let barRight  = cx + r
            let barTop    = cy - r * 0.145
            let barBottom = cy + r * 0.145
            var bar = Path()
            bar.addRoundedRect(in: CGRect(x: barLeft, y: barTop,
                                          width: barRight - barLeft, height: barBottom - barTop),
                               cornerSize: CGSize(width: 2, height: 2))
            ctx.fill(bar, with: .color(Color(red: 0.26, green: 0.52, blue: 0.96)))

            // Re-punch the inner circle over the bar so it looks like a G cutout
            ctx.fill(inner, with: .color(.white))
        }
    }
}
