import SwiftUI

// MARK: - Parsed Section Model

struct ParsedSection {
    enum Kind {
        case medical, nutrition, behavioral, overall, unknown

        var title: String {
            switch self {
            case .medical:    return "MEDICAL ANALYSIS"
            case .nutrition:  return "NUTRITION & METABOLISM"
            case .behavioral: return "BEHAVIORAL INSIGHT"
            case .overall:    return "OVERALL SYNTHESIS"
            case .unknown:    return "ANALYSIS"
            }
        }

        var icon: String {
            switch self {
            case .medical:    return "stethoscope"
            case .nutrition:  return "leaf.fill"
            case .behavioral: return "brain.head.profile"
            case .overall:    return "sparkles"
            case .unknown:    return "doc.text.fill"
            }
        }

        var color: Color {
            switch self {
            case .medical:    return Color(hex: "#5BC8FF")
            case .nutrition:  return Color(hex: "#4CD964")
            case .behavioral: return Color(hex: "#BF5AF2")
            case .overall:    return Color(hex: "#F0A830")
            case .unknown:    return AppColors.textSecondary
            }
        }
    }

    let kind: Kind
    let body: String
}

// MARK: - Parser

enum CoachReportParser {
    private static let prefixes: [(String, ParsedSection.Kind)] = [
        ("MEDICAL ANALYSIS", .medical),
        ("NUTRITION & METABOLISM", .nutrition),
        ("NUTRITION AND METABOLISM", .nutrition),
        ("BEHAVIORAL INSIGHT", .behavioral),
        ("OVERALL SYNTHESIS", .overall),
        ("OVERALL COACH", .overall),
        // Legacy named professionals (backward compat)
        ("DR. REYES", .medical),
        ("SOFIA NAKAMURA", .nutrition),
        ("JAMES OKAFOR", .behavioral),
    ]

    static func parse(_ text: String) -> [ParsedSection] {
        text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { para -> ParsedSection in
                guard let colonRange = para.range(of: ":") else {
                    return ParsedSection(kind: .unknown, body: para)
                }
                let prefix = String(para[para.startIndex..<colonRange.lowerBound]).uppercased()
                let body   = String(para[colonRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                let kind   = prefixes.first { prefix.contains($0.0) }?.1 ?? .unknown
                return ParsedSection(kind: kind, body: body)
            }
    }
}

// MARK: - Weekly / Monthly Report Card

struct CoachReportCard: View {
    let report: CoachReport
    let periodLabel: String
    @EnvironmentObject var appState: AppState
    @State private var showPaywall = false

    private var isGenerating: Bool { appState.generatingCoachReportId == report.id }
    private var isPro: Bool { appState.isPro }

    private var sections: [ParsedSection] {
        guard let text = report.report else { return [] }
        return CoachReportParser.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader
            accentRule(color: AppColors.accent)
            if isGenerating || report.report == nil {
                generatingState(label: "ANALYZING", color: AppColors.accent)
            } else {
                ZStack {
                    sectionsContent
                        .blur(radius: isPro ? 0 : 9)
                        .allowsHitTesting(isPro)
                    if !isPro { proGate }
                }
                .clipped()
            }
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    LinearGradient(
                        colors: [AppColors.accent.opacity(0.5), AppColors.border.opacity(0.2)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    // MARK: Header

    private var cardHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(report.type == .weekly ? "WEEKLY" : "MONTHLY")
                    .font(.system(size: 8, weight: .black))
                    .tracking(2.5)
                    .foregroundStyle(AppColors.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(AppColors.accentDim)
                    .cornerRadius(4)
                Text(periodLabel)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppColors.text)
            }
            Spacer()
            Image(uiImage: UIImage(named: "AppIcon") ?? UIImage())
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
                .cornerRadius(8)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    // MARK: Sections

    private var sectionsContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.offset) { i, section in
                sectionRow(section)
                if i < sections.count - 1 {
                    coachDashedDivider.padding(.horizontal, 16)
                }
            }
        }
        .padding(.bottom, 10)
    }
}

// MARK: - Comparison Report Card

struct ComparisonReportCard: View {
    let report: CoachReport
    @EnvironmentObject var appState: AppState
    @State private var showPaywall = false

    private var isPro: Bool { appState.isPro }
    private var isGenerating: Bool { appState.generatingCoachReportId == report.id }

    private var eventA: NightEvent? {
        report.eventAId.flatMap { id in appState.events.first { $0.id == id } }
    }
    private var eventB: NightEvent? {
        report.eventBId.flatMap { id in appState.events.first { $0.id == id } }
    }
    private var sections: [ParsedSection] {
        guard let text = report.report else { return [] }
        return CoachReportParser.parse(text)
    }

    private let vsColor = Color(hex: "#BF5AF2")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            comparisonHeader
            accentRule(color: vsColor)
            if isGenerating || report.report == nil {
                generatingState(label: "COMPARING", color: vsColor)
            } else {
                ZStack {
                    sectionsContent
                        .blur(radius: isPro ? 0 : 9)
                        .allowsHitTesting(isPro)
                    if !isPro { proGate }
                }
                .clipped()
            }
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    LinearGradient(
                        colors: [vsColor.opacity(0.45), AppColors.border.opacity(0.2)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    private var comparisonHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COMPARISON")
                .font(.system(size: 8, weight: .black))
                .tracking(2.5)
                .foregroundStyle(vsColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(vsColor.opacity(0.12))
                .cornerRadius(4)

            HStack(alignment: .center, spacing: 10) {
                nightSlot(label: "A", event: eventA, color: Color(hex: "#5BC8FF"))
                Text("VS")
                    .font(.system(size: 10, weight: .black))
                    .tracking(2)
                    .foregroundStyle(vsColor.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(vsColor.opacity(0.1))
                    .cornerRadius(6)
                nightSlot(label: "B", event: eventB, color: Color(hex: "#BF5AF2"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private func nightSlot(label: String, event: NightEvent?, color: Color) -> some View {
        VStack(alignment: label == "A" ? .leading : .trailing, spacing: 2) {
            Text("NIGHT \(label)")
                .font(.system(size: 8, weight: .black))
                .tracking(1.5)
                .foregroundStyle(color.opacity(0.7))
            Text(event?.displayName ?? "—")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.text)
                .lineLimit(1)
            if let e = event {
                Text(e.startTime, format: .dateTime.month(.abbreviated).day().year())
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: label == "A" ? .leading : .trailing)
    }

    private var sectionsContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.offset) { i, section in
                sectionRow(section)
                if i < sections.count - 1 {
                    coachDashedDivider.padding(.horizontal, 16)
                }
            }
        }
        .padding(.bottom, 10)
    }
}

// MARK: - Shared rendering helpers (used by both card types)

private extension CoachReportCard {
    func sectionRow(_ section: ParsedSection) -> some View { SectionRow(section: section) }
    var proGate: some View { _proGate(showPaywall: $showPaywall) }
    var cardBackground: some View { _cardBackground() }
}

private extension ComparisonReportCard {
    func sectionRow(_ section: ParsedSection) -> some View { SectionRow(section: section) }
    var proGate: some View { _proGate(showPaywall: $showPaywall) }
    var cardBackground: some View { _cardBackground() }
}

// MARK: - Collapsible Section Row

private struct SectionRow: View {
    let section: ParsedSection
    @State private var collapsed = true

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(section.kind.color)
                .frame(width: 3)
                .cornerRadius(1.5)
                .padding(.vertical, 14)
                .padding(.leading, 16)

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        collapsed.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: section.kind.icon)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(section.kind.color)
                        Text(section.kind.title)
                            .font(.system(size: 9, weight: .black))
                            .tracking(2)
                            .foregroundStyle(section.kind.color)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(section.kind.color.opacity(0.6))
                            .rotationEffect(.degrees(collapsed ? -90 : 0))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(section.kind.color.opacity(0.12))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)

                if !collapsed {
                    Text(section.body)
                        .font(.system(size: 13, design: .serif))
                        .foregroundStyle(AppColors.text)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 16)
            .padding(.top, 14)
            .padding(.bottom, collapsed ? 10 : 14)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: collapsed)
    }
}

private func accentRule(color: Color) -> some View {
    Rectangle()
        .fill(
            LinearGradient(
                colors: [color, color.opacity(0.3), .clear],
                startPoint: .leading, endPoint: .trailing
            )
        )
        .frame(height: 1)
}

private func generatingState(label: String, color: Color) -> some View {
    VStack(spacing: 18) {
        CoachEKGScanLine(accentColor: color)
            .frame(height: 52)
            .padding(.horizontal, 4)
        VStack(spacing: 5) {
            Text(label)
                .font(.system(size: 9, weight: .black))
                .tracking(2.5)
                .foregroundStyle(color)
            Text("Building your health report…")
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textSecondary)
        }
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 20)
    .padding(.vertical, 30)
}

private func _proGate(showPaywall: Binding<Bool>) -> some View {
    VStack(spacing: 14) {
        ZStack {
            Circle()
                .fill(AppColors.accent.opacity(0.12))
                .frame(width: 52, height: 52)
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 24))
                .foregroundStyle(AppColors.accent)
        }
        VStack(spacing: 5) {
            Text("PRO REPORT")
                .font(.system(size: 12, weight: .black))
                .tracking(2)
                .foregroundStyle(AppColors.text)
            Text("Your AI analysis is ready. Upgrade to read it.")
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        Button { showPaywall.wrappedValue = true } label: {
            Text("Upgrade to Pro")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 24)
                .padding(.vertical, 11)
                .background(
                    LinearGradient(
                        colors: [AppColors.accentWarm, AppColors.accent],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .cornerRadius(24)
                .shadow(color: AppColors.accent.opacity(0.5), radius: 10, y: 4)
        }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 36)
    .padding(.horizontal, 20)
}

private func _cardBackground() -> some View {
    ZStack {
        LinearGradient(
            colors: [AppColors.surfaceTop, AppColors.surfaceBottom],
            startPoint: .top, endPoint: .bottom
        )
        Canvas { ctx, size in
            let sp: CGFloat = 20
            for x in stride(from: sp / 2, through: size.width, by: sp) {
                for y in stride(from: sp / 2, through: size.height, by: sp) {
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x - 0.7, y: y - 0.7, width: 1.4, height: 1.4)),
                        with: .color(.white.opacity(0.045))
                    )
                }
            }
        }
    }
}

private var coachDashedDivider: some View {
    Canvas { ctx, size in
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: size.width, y: 0))
        ctx.stroke(path, with: .color(.white.opacity(0.1)), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
    }
    .frame(height: 1)
}

// MARK: - EKG Scan Line (coach variant)

private struct CoachEKGScanLine: View {
    let accentColor: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.016)) { tl in
            Canvas { ctx, size in
                let t = CGFloat(tl.date.timeIntervalSinceReferenceDate)
                let cycleLen: CGFloat = 2.2
                let progress = (t / cycleLen).truncatingRemainder(dividingBy: 1.0)
                let scanX = progress * size.width
                let midY = size.height / 2

                var ahead = Path()
                ahead.move(to: CGPoint(x: scanX, y: midY))
                ahead.addLine(to: CGPoint(x: size.width, y: midY))
                ctx.stroke(ahead, with: .color(.white.opacity(0.07)), lineWidth: 1)

                if scanX > 0 {
                    var path = Path()
                    let step: CGFloat = 2
                    var x: CGFloat = 0
                    while x <= scanX {
                        let y = ekgY(x / size.width, midY: midY, h: size.height)
                        if x == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                        x += step
                    }
                    ctx.stroke(
                        path,
                        with: .linearGradient(
                            Gradient(stops: [
                                .init(color: accentColor.opacity(0.05), location: 0),
                                .init(color: accentColor.opacity(0.9), location: 1)
                            ]),
                            startPoint: .zero,
                            endPoint: CGPoint(x: scanX, y: midY)
                        ),
                        lineWidth: 2
                    )
                    let dotY = ekgY(scanX / size.width, midY: midY, h: size.height)
                    ctx.fill(Path(ellipseIn: CGRect(x: scanX - 5, y: dotY - 5, width: 10, height: 10)), with: .color(accentColor.opacity(0.25)))
                    ctx.fill(Path(ellipseIn: CGRect(x: scanX - 3, y: dotY - 3, width: 6, height: 6)), with: .color(accentColor))
                }
            }
        }
    }

    private func ekgY(_ norm: CGFloat, midY: CGFloat, h: CGFloat) -> CGFloat {
        let s = norm.truncatingRemainder(dividingBy: 1.0)
        if s < 0.08 { return midY }
        if s < 0.14 { return midY - h * 0.13 * sin((s - 0.08) / 0.06 * .pi) }
        if s < 0.26 { return midY }
        if s < 0.30 { return midY + h * 0.09 * ((s - 0.26) / 0.04) }
        if s < 0.34 { return midY - h * 0.44 * sin((s - 0.30) / 0.04 * .pi) }
        if s < 0.38 { return midY + h * 0.20 * sin((s - 0.34) / 0.04 * .pi) }
        if s < 0.48 { return midY }
        if s < 0.62 { return midY - h * 0.16 * sin((s - 0.48) / 0.14 * .pi) }
        return midY
    }
}
