import SwiftUI

// MARK: - AI Report Card (in-app, dark medical theme)

struct AIReportCard: View {
    let report: String?
    let isGenerating: Bool
    let isPro: Bool
    @State private var showPaywall = false

    private static let sectionLabels = ["OVERVIEW", "PHYSIOLOGY", "INSIGHT"]

    private var paragraphs: [String] {
        guard let text = report else { return [] }
        let parts = text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.count >= 2 ? parts : [text]
    }

    var body: some View {
        if report != nil || isGenerating {
            cardView
                .padding(.horizontal)
                .sheet(isPresented: $showPaywall) { PaywallView() }
        }
    }

    // MARK: - Card Shell

    private var cardView: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader
            goldRule
            if isGenerating {
                ekgLoadingState
            } else {
                reportSections
            }
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    LinearGradient(
                        colors: [AppColors.accent.opacity(0.65), AppColors.border.opacity(0.35)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Header

    private var cardHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            TracksipLogoMark(size: 36)

            VStack(alignment: .leading, spacing: 1) {
                Text("TRACKSIP")
                    .font(.system(size: 8, weight: .black))
                    .tracking(3.5)
                    .foregroundStyle(AppColors.accent)
                Text("HEALTH ANALYSIS")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(AppColors.text)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text("AI REPORT")
                    .font(.system(size: 7, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(AppColors.textTertiary)
                Text(Date(), format: .dateTime.day().month(.abbreviated).year())
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppColors.textSecondary)
                if !isPro {
                    Text("PRO")
                        .font(.system(size: 7, weight: .black))
                        .tracking(1.5)
                        .foregroundStyle(AppColors.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(AppColors.accentDim)
                        .cornerRadius(4)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    // MARK: - Gold Rule

    private var goldRule: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [AppColors.accent, AppColors.accent.opacity(0.3), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .frame(height: 1)
    }

    // MARK: - EKG Loading State

    private var ekgLoadingState: some View {
        VStack(spacing: 18) {
            EKGScanLine()
                .frame(height: 52)
                .padding(.horizontal, 4)

            VStack(spacing: 5) {
                Text("ANALYZING YOUR NIGHT")
                    .font(.system(size: 9, weight: .black))
                    .tracking(2.5)
                    .foregroundStyle(AppColors.accent)
                Text("Building your personalized health report…")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 30)
    }

    // MARK: - Report Sections

    private var reportSections: some View {
        ZStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { i, para in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Capsule()
                                .fill(AppColors.accent)
                                .frame(width: 3, height: 14)
                            if i < AIReportCard.sectionLabels.count {
                                Text(AIReportCard.sectionLabels[i])
                                    .font(.system(size: 9, weight: .black))
                                    .tracking(2.5)
                                    .foregroundStyle(AppColors.accent)
                            }
                        }

                        Text(para)
                            .font(.system(size: 14, design: .serif))
                            .foregroundStyle(AppColors.text)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    if i < paragraphs.count - 1 {
                        DashedDivider()
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, isPro ? 6 : 0)
            }
            .blur(radius: isPro ? 0 : 9)
            .allowsHitTesting(isPro)

            if !isPro { proGate }
        }
        .clipped()
    }

    private var proGate: some View {
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

            Button { showPaywall = true } label: {
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

    // MARK: - Background

    private var cardBackground: some View {
        ZStack {
            LinearGradient(
                colors: [AppColors.surfaceTop, AppColors.surfaceBottom],
                startPoint: .top, endPoint: .bottom
            )
            // Dot-grid: medical chart paper feel
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
}

// MARK: - EKG Scan Line

private struct EKGScanLine: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.016)) { tl in
            Canvas { ctx, size in
                let t = CGFloat(tl.date.timeIntervalSinceReferenceDate)
                let cycleLen: CGFloat = 2.2
                let progress = (t / cycleLen).truncatingRemainder(dividingBy: 1.0)
                let scanX = progress * size.width
                let midY = size.height / 2
                let gold = Color(hex: "#F0A830")

                // Flat baseline ahead of scan
                var ahead = Path()
                ahead.move(to: CGPoint(x: scanX, y: midY))
                ahead.addLine(to: CGPoint(x: size.width, y: midY))
                ctx.stroke(ahead, with: .color(.white.opacity(0.07)), lineWidth: 1)

                // EKG waveform behind scan
                if scanX > 0 {
                    var path = Path()
                    let step: CGFloat = 2
                    var x: CGFloat = 0
                    while x <= scanX {
                        let y = ekgY(x / size.width, midY: midY, h: size.height)
                        if x == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                        x += step
                    }
                    ctx.stroke(
                        path,
                        with: .linearGradient(
                            Gradient(stops: [
                                .init(color: gold.opacity(0.05), location: 0),
                                .init(color: gold.opacity(0.95), location: 1)
                            ]),
                            startPoint: .zero,
                            endPoint: CGPoint(x: scanX, y: midY)
                        ),
                        lineWidth: 2
                    )

                    // Scanning dot with glow
                    let dotY = ekgY(scanX / size.width, midY: midY, h: size.height)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: scanX - 5, y: dotY - 5, width: 10, height: 10)),
                        with: .color(gold.opacity(0.25))
                    )
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: scanX - 3, y: dotY - 3, width: 6, height: 6)),
                        with: .color(gold)
                    )
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

// MARK: - Dashed Divider

private struct DashedDivider: View {
    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: size.width, y: 0))
            ctx.stroke(
                path,
                with: .color(.white.opacity(0.12)),
                style: StrokeStyle(lineWidth: 1, dash: [4, 5])
            )
        }
        .frame(height: 1)
    }
}

// MARK: - Tracksip Logo Mark (coupe glass + BAC wave, pure SwiftUI)

struct TracksipLogoMark: View {
    let size: CGFloat
    var foregroundColor: Color = .white
    var waveColor: Color = Color(hex: "#5BC8FF")

    var body: some View {
        Canvas { ctx, _ in
            let w = size
            let h = size

            // ── Bowl ──────────────────────────────────────────────────
            // Wide ellipse arc at the top, closing into a narrow V at bottom
            let bowlTop: CGFloat    = h * 0.05
            let bowlBottom: CGFloat = h * 0.62
            let bowlHalfW: CGFloat  = w * 0.46
            let bowlNeckW: CGFloat  = w * 0.10

            var bowl = Path()
            bowl.move(to: CGPoint(x: w * 0.5 - bowlHalfW, y: bowlTop))
            // Left side: arc down to neck
            bowl.addCurve(
                to: CGPoint(x: w * 0.5 - bowlNeckW, y: bowlBottom),
                control1: CGPoint(x: w * 0.5 - bowlHalfW, y: bowlTop + h * 0.30),
                control2: CGPoint(x: w * 0.5 - bowlNeckW, y: bowlBottom - h * 0.08)
            )
            // Right side: mirror
            bowl.addLine(to: CGPoint(x: w * 0.5 + bowlNeckW, y: bowlBottom))
            bowl.addCurve(
                to: CGPoint(x: w * 0.5 + bowlHalfW, y: bowlTop),
                control1: CGPoint(x: w * 0.5 + bowlNeckW, y: bowlBottom - h * 0.08),
                control2: CGPoint(x: w * 0.5 + bowlHalfW, y: bowlTop + h * 0.30)
            )
            // Top rim
            bowl.addLine(to: CGPoint(x: w * 0.5 - bowlHalfW, y: bowlTop))
            bowl.closeSubpath()

            // Draw bowl outline
            ctx.stroke(
                bowl,
                with: .linearGradient(
                    Gradient(colors: [foregroundColor.opacity(0.9), foregroundColor.opacity(0.5)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: h)
                ),
                lineWidth: max(1.2, w * 0.03)
            )

            // ── BAC wave clipped to bowl ───────────────────────────────
            let waveY: CGFloat = bowlTop + (bowlBottom - bowlTop) * 0.55
            var wavePath = Path()
            let pts = 60
            for i in 0...pts {
                let t = CGFloat(i) / CGFloat(pts)
                let xPos = (w * 0.5 - bowlHalfW) + t * (bowlHalfW * 2)
                let amp = h * 0.10 * exp(-pow((t - 0.40) / 0.22, 2))
                let yPos = waveY - amp * sin(t * .pi * 3.5)
                if i == 0 { wavePath.move(to: CGPoint(x: xPos, y: yPos)) }
                else { wavePath.addLine(to: CGPoint(x: xPos, y: yPos)) }
            }
            // Scope the clip inside drawLayer so it resets automatically
            ctx.drawLayer { clipped in
                clipped.clip(to: bowl)
                clipped.stroke(
                    wavePath,
                    with: .linearGradient(
                        Gradient(colors: [waveColor.opacity(0.5), waveColor, waveColor.opacity(0.3)]),
                        startPoint: CGPoint(x: 0, y: waveY),
                        endPoint: CGPoint(x: w, y: waveY)
                    ),
                    lineWidth: max(1.0, w * 0.025)
                )
            }

            // ── Stem & Base ───────────────────────────────────────────
            let stemTop: CGFloat   = bowlBottom
            let stemBot: CGFloat   = h * 0.87
            let baseHalfW: CGFloat = w * 0.32

            var stem = Path()
            stem.move(to: CGPoint(x: w * 0.5, y: stemTop))
            stem.addLine(to: CGPoint(x: w * 0.5, y: stemBot))
            stem.move(to: CGPoint(x: w * 0.5 - baseHalfW, y: stemBot))
            stem.addLine(to: CGPoint(x: w * 0.5 + baseHalfW, y: stemBot))

            ctx.stroke(
                stem,
                with: .color(foregroundColor.opacity(0.7)),
                lineWidth: max(1.0, w * 0.025)
            )
        }
        .frame(width: size, height: size)
    }
}

// MARK: - RecoverySeverity color (SwiftUI layer)

extension RecoverySeverity {
    var color: Color {
        switch self {
        case .mild:     return Color(hex: "#4CD964")
        case .moderate: return Color(hex: "#F0A830")
        case .rough:    return Color(hex: "#FF6B6B")
        }
    }
}

// MARK: - Unified Analysis Section

struct AnalysisSection {
    enum Kind {
        case physiology, insight
        case recovery, hydration
        case unknown

        var title: String {
            switch self {
            case .physiology: return "PHYSIOLOGY"
            case .insight:    return "NEXT TIME"
            case .recovery:   return "RECOVERY"
            case .hydration:  return "HYDRATION"
            case .unknown:    return "ANALYSIS"
            }
        }

        var icon: String {
            switch self {
            case .physiology: return "waveform.path.ecg"
            case .insight:    return "brain.head.profile"
            case .recovery:   return "cross.case.fill"
            case .hydration:  return "drop.fill"
            case .unknown:    return "sparkles"
            }
        }

        var color: Color {
            switch self {
            case .physiology: return Color(hex: "#5BC8FF")
            case .insight:    return Color(hex: "#BF5AF2")
            case .recovery:   return Color(hex: "#4CD964")
            case .hydration:  return AppColors.water
            case .unknown:    return AppColors.accent
            }
        }
    }

    let kind: Kind
    let body: String
}

// MARK: - Parsers

enum NightReportParser {
    private static let order: [AnalysisSection.Kind] = [.physiology, .insight]

    static func parse(_ text: String) -> [AnalysisSection] {
        let paras = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return paras.enumerated().map { i, para in
            let body: String
            if let colon = para.range(of: ":") {
                body = String(para[colon.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                body = para
            }
            let kind = i < order.count ? order[i] : .unknown
            return AnalysisSection(kind: kind, body: body.isEmpty ? para : body)
        }
    }
}

enum RecoveryAnalysisParser {
    static func parse(_ text: String) -> [AnalysisSection] {
        let paras = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // New format: single unlabeled paragraph
        if paras.count == 1 {
            return [AnalysisSection(kind: .recovery, body: paras[0])]
        }

        // Legacy format: labeled RECOVERY / HYDRATION paragraphs
        return paras.compactMap { para -> AnalysisSection? in
            guard let colon = para.range(of: ":") else { return nil }
            let prefix = String(para[para.startIndex..<colon.lowerBound]).uppercased()
            let body = String(para[colon.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if prefix.contains("RECOVERY") { return AnalysisSection(kind: .recovery, body: body) }
            if prefix.contains("HYDRATION") { return AnalysisSection(kind: .hydration, body: body) }
            return nil
        }
    }
}

// MARK: - Collapsible Row

private struct AnalysisSectionRow: View {
    let section: AnalysisSection
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

// MARK: - EKG Line

private struct AnalysisEKGLine: View {
    let accentColor: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.016)) { tl in
            Canvas { ctx, size in
                let t = CGFloat(tl.date.timeIntervalSinceReferenceDate)
                let progress = (t / 2.2).truncatingRemainder(dividingBy: 1.0)
                let scanX = progress * size.width
                let midY = size.height / 2

                var ahead = Path()
                ahead.move(to: CGPoint(x: scanX, y: midY))
                ahead.addLine(to: CGPoint(x: size.width, y: midY))
                ctx.stroke(ahead, with: .color(.white.opacity(0.07)), lineWidth: 1)

                if scanX > 0 {
                    var path = Path()
                    var x: CGFloat = 0
                    while x <= scanX {
                        let y = ekgY(x / size.width, midY: midY, h: size.height)
                        if x == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                        x += 2
                    }
                    ctx.stroke(path, with: .linearGradient(
                        Gradient(stops: [
                            .init(color: accentColor.opacity(0.05), location: 0),
                            .init(color: accentColor.opacity(0.9), location: 1)
                        ]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: scanX, y: midY)
                    ), lineWidth: 2)
                    let dotY = ekgY(scanX / size.width, midY: midY, h: size.height)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: scanX-5, y: dotY-5, width: 10, height: 10)),
                        with: .color(accentColor.opacity(0.25))
                    )
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: scanX-3, y: dotY-3, width: 6, height: 6)),
                        with: .color(accentColor)
                    )
                }
            }
        }
    }

    private func ekgY(_ norm: CGFloat, midY: CGFloat, h: CGFloat) -> CGFloat {
        let s = norm.truncatingRemainder(dividingBy: 1.0)
        if s < 0.08 { return midY }
        if s < 0.14 { return midY - h * 0.13 * sin((s-0.08)/0.06 * .pi) }
        if s < 0.26 { return midY }
        if s < 0.30 { return midY + h * 0.09 * ((s-0.26)/0.04) }
        if s < 0.34 { return midY - h * 0.44 * sin((s-0.30)/0.04 * .pi) }
        if s < 0.38 { return midY + h * 0.20 * sin((s-0.34)/0.04 * .pi) }
        if s < 0.48 { return midY }
        if s < 0.62 { return midY - h * 0.16 * sin((s-0.48)/0.14 * .pi) }
        return midY
    }
}

// MARK: - Unified Night Analysis Card

struct NightAnalysisCard: View {
    let eventId: String
    @EnvironmentObject var appState: AppState
    @State private var showPaywall = false

    private var event: NightEvent? {
        appState.events.first { $0.id == eventId }
    }
    private var recovery: NightRecovery? {
        appState.nightRecoveries.first { $0.id == eventId }
    }
    private var severity: RecoverySeverity { recovery?.severity ?? .mild }
    private var isGeneratingNight: Bool {
        appState.generatingReportForEventId == eventId
    }
    private var isGeneratingRecovery: Bool {
        appState.generatingRecoveryForEventId == eventId
    }
    private var isFailedNight: Bool {
        appState.failedReportEventIds.contains(eventId)
    }
    private var isFailedRecovery: Bool {
        appState.failedRecoveryEventIds.contains(eventId)
    }
    private var isPro: Bool { appState.isPro }
    private var hasEnded: Bool { event?.endTime != nil }

    private var isAtFreeLimit: Bool {
        guard !isPro else { return false }
        guard event?.aiReport == nil, !isGeneratingNight else { return false }
        return !appState.canGenerateNightReport
    }

    private var themeColor: Color {
        recovery != nil ? severity.color : AppColors.accent
    }
    private var nightSections: [AnalysisSection] {
        guard let text = event?.aiReport else { return [] }
        return NightReportParser.parse(text)
    }
    private var recoverySections: [AnalysisSection] {
        guard let text = recovery?.report else { return [] }
        return RecoveryAnalysisParser.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader
            themeAccentRule
            if isGeneratingNight {
                analysisLoading(label: "SCANNING", color: AppColors.accent)
            } else if isAtFreeLimit {
                freeReportLimitGate
            } else if event?.aiReport != nil {
                cardBody
            } else if isFailedNight {
                analysisFailure(label: "ANALYSIS FAILED") {
                    appState.retryNightReport(eventId: eventId)
                }
            } else {
                analysisLoading(label: "SCANNING", color: AppColors.accent)
            }
        }
        .background(dotGridBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    LinearGradient(
                        colors: [themeColor.opacity(0.5), AppColors.border.opacity(0.2)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    // MARK: Header

    private var cardHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Image(uiImage: UIImage(named: "AppIcon") ?? UIImage())
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 4) {
                    Text("NIGHT ANALYSIS")
                        .font(.system(size: 8, weight: .black))
                        .tracking(2.5)
                        .foregroundStyle(AppColors.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(AppColors.accentDim)
                        .cornerRadius(4)
                    Text(event?.displayName ?? "—")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppColors.text)
                        .lineLimit(1)
                }

                Spacer()

                if let event = event {
                    Text(event.startTime, format: .dateTime.month(.abbreviated).day())
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }

            if let r = recovery {
                HStack(spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: r.severity.icon)
                            .font(.system(size: 9, weight: .semibold))
                        Text(r.severity.label)
                            .font(.system(size: 9, weight: .black))
                            .tracking(2)
                    }
                    .foregroundStyle(r.severity.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(r.severity.color.opacity(0.14))
                    .cornerRadius(5)

                    Text("RECOVERY")
                        .font(.system(size: 8, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(AppColors.textTertiary)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    // MARK: Body

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(nightSections.enumerated()), id: \.offset) { i, section in
                AnalysisSectionRow(section: section)
                dashedDivider
            }

            if hasEnded {
                recoveryDivider
                if isGeneratingRecovery {
                    analysisLoading(label: "RECOVERY", color: severity.color)
                } else if isFailedRecovery {
                    analysisFailure(label: "RECOVERY FAILED") {
                        appState.retryRecoveryBrief(eventId: eventId)
                    }
                } else if recovery != nil && recovery?.report == nil {
                    analysisLoading(label: "RECOVERY", color: severity.color)
                } else {
                    ForEach(Array(recoverySections.enumerated()), id: \.offset) { i, section in
                        AnalysisSectionRow(section: section)
                        if i < recoverySections.count - 1 { dashedDivider }
                    }
                }
            }
        }
        .padding(.bottom, 10)
    }

    // MARK: Sub-views

    private var recoveryDivider: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(LinearGradient(
                    colors: [.clear, AppColors.border.opacity(0.4)],
                    startPoint: .leading, endPoint: .trailing
                ))
                .frame(height: 1)
            Text("RECOVERY")
                .font(.system(size: 7, weight: .black))
                .tracking(2.5)
                .foregroundStyle(AppColors.textTertiary)
            Rectangle()
                .fill(LinearGradient(
                    colors: [AppColors.border.opacity(0.4), .clear],
                    startPoint: .leading, endPoint: .trailing
                ))
                .frame(height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func analysisLoading(label: String, color: Color) -> some View {
        VStack(spacing: 16) {
            AnalysisEKGLine(accentColor: color)
                .frame(height: 48)
                .padding(.horizontal, 4)
            VStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 9, weight: .black))
                    .tracking(2.5)
                    .foregroundStyle(color)
                Text("AI processing…")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 26)
    }

    private func analysisFailure(label: String, retryAction: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 26))
                .foregroundStyle(Color.orange)
            VStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 9, weight: .black))
                    .tracking(2.5)
                    .foregroundStyle(Color.orange)
                Text("Could not reach AI service")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)
            }
            Button(action: retryAction) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                    Text("RETRY")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.5)
                }
                .foregroundStyle(AppColors.accent)
                .padding(.horizontal, 20)
                .padding(.vertical, 9)
                .background(AppColors.accentDim)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 26)
    }

    private var freeReportLimitGate: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AppColors.accent.opacity(0.12))
                    .frame(width: 60, height: 60)
                VStack(spacing: 2) {
                    Text("\(AppState.freeMonthlyReportLimit)")
                        .font(.system(size: 20, weight: .black, design: .monospaced))
                        .foregroundStyle(AppColors.accent)
                    Text("/\(AppState.freeMonthlyReportLimit)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppColors.accent.opacity(0.6))
                }
            }

            VStack(spacing: 6) {
                Text("MONTHLY LIMIT REACHED")
                    .font(.system(size: 11, weight: .black))
                    .tracking(1.8)
                    .foregroundStyle(AppColors.text)
                Text("You've used all \(AppState.freeMonthlyReportLimit) free AI reports this month. Upgrade for unlimited night analysis.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button { showPaywall = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 12))
                    Text("Upgrade for Unlimited")
                        .font(.system(size: 13, weight: .bold))
                }
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

    private var themeAccentRule: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [themeColor, themeColor.opacity(0.3), .clear],
                startPoint: .leading, endPoint: .trailing
            ))
            .frame(height: 1)
    }

    private var dashedDivider: some View {
        Canvas { ctx, size in
            var path = Path()
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: size.width, y: 0))
            ctx.stroke(path, with: .color(.white.opacity(0.08)),
                       style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
        }
        .frame(height: 1)
        .padding(.horizontal, 16)
    }

    private var dotGridBackground: some View {
        ZStack {
            LinearGradient(
                colors: [AppColors.surfaceTop, AppColors.surfaceBottom],
                startPoint: .top, endPoint: .bottom
            )
            Canvas { ctx, size in
                let sp: CGFloat = 20
                for x in stride(from: sp/2, through: size.width, by: sp) {
                    for y in stride(from: sp/2, through: size.height, by: sp) {
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: x-0.7, y: y-0.7, width: 1.4, height: 1.4)),
                            with: .color(.white.opacity(0.04))
                        )
                    }
                }
            }
        }
    }
}

