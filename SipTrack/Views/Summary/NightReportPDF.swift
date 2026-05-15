import SwiftUI
import UIKit

// MARK: - Share Sheet wrapper

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Data model

struct NightReportData {
    let event: NightEvent
    let report: String
    let drinkCount: Int
    let peakBAC: Double
    let calories: Double
    let waterCount: Int
    let standardDrinks: Double
    let userProfile: UserProfile
}

// MARK: - PDF Export

func exportNightReportPDF(_ data: NightReportData) -> URL? {
    let pageW: CGFloat = 820
    let view = NightReportPDFPage(data: data)
        .environment(\.colorScheme, .light)

    let renderer = ImageRenderer(content: view)
    renderer.proposedSize = .init(width: pageW, height: nil)
    renderer.scale = 2.0
    guard let image = renderer.uiImage else { return nil }

    let pageSize = image.size
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("tracksip-health-report.pdf")

    let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
    try? pdfRenderer.writePDF(to: url) { ctx in
        ctx.beginPage()
        image.draw(in: CGRect(origin: .zero, size: pageSize))
    }
    return url
}

// MARK: - Full PDF Page View

struct NightReportPDFPage: View {
    let data: NightReportData

    private static let gold     = Color(hex: "#F0A830")
    private static let navy     = Color(hex: "#0A1628")
    private static let cream    = Color(hex: "#F7F4EF")
    private static let ink      = Color(hex: "#0D1117")
    private static let inkLight = Color(hex: "#4A5568")
    private static let rule     = Color(hex: "#D4CCBC")

    private var paragraphs: [String] {
        data.report
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    private static let sectionTitles = ["OVERVIEW", "PHYSIOLOGY", "HEALTH INSIGHT"]
    private static let sectionNums   = ["01", "02", "03"]

    private var eventDateStr: String {
        let f = DateFormatter(); f.dateFormat = "MMMM d, yyyy"
        return f.string(from: data.event.startTime)
    }
    private var durationStr: String {
        let d = data.event.duration
        let h = Int(d / 3600); let m = Int((d.truncatingRemainder(dividingBy: 3600)) / 60)
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
    private var ageStr: String {
        guard let by = data.userProfile.birthYear else { return "N/A" }
        return "\(Calendar.current.component(.year, from: Date()) - by)"
    }

    var body: some View {
        VStack(spacing: 0) {
            navyHeader
            metadataStrip
            goldRulePDF
            reportBody
            goldRulePDF
            statsSection
            pageFooter
        }
        .background(NightReportPDFPage.cream)
        .frame(width: 820)
    }

    // MARK: – Navy Header

    private var navyHeader: some View {
        ZStack {
            NightReportPDFPage.navy

            // Subtle dot-grid overlay
            Canvas { ctx, size in
                let sp: CGFloat = 28
                for x in stride(from: sp, through: size.width, by: sp) {
                    for y in stride(from: sp, through: size.height, by: sp) {
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: x - 0.6, y: y - 0.6, width: 1.2, height: 1.2)),
                            with: .color(.white.opacity(0.06))
                        )
                    }
                }
            }

            // Diagonal gold accent stripe
            Canvas { ctx, size in
                var path = Path()
                path.move(to: CGPoint(x: size.width * 0.70, y: 0))
                path.addLine(to: CGPoint(x: size.width, y: 0))
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.addLine(to: CGPoint(x: size.width * 0.78, y: size.height))
                path.closeSubpath()
                ctx.fill(path, with: .color(NightReportPDFPage.gold.opacity(0.06)))
            }

            VStack(spacing: 10) {
                // Logo + wordmark row
                HStack(spacing: 16) {
                    if let icon = UIImage(named: "AppIcon") {
                        Image(uiImage: icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 64, height: 64)
                            .cornerRadius(14)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TRACKSIP")
                            .font(.system(size: 11, weight: .black))
                            .tracking(5)
                            .foregroundStyle(NightReportPDFPage.gold)
                        Text("Health Intelligence Platform")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.50))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("HEALTH ANALYSIS REPORT")
                            .font(.system(size: 9, weight: .black))
                            .tracking(2)
                            .foregroundStyle(NightReportPDFPage.gold)
                        Text("CONFIDENTIAL")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(2)
                            .foregroundStyle(.white.opacity(0.30))
                    }
                }
                .padding(.horizontal, 48)

                // Event name banner
                Text(data.event.displayName.uppercased())
                    .font(.system(size: 28, weight: .black, design: .serif))
                    .tracking(1)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 48)

                // Gold underline
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [NightReportPDFPage.gold, NightReportPDFPage.gold.opacity(0.2), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(height: 1.5)
                    .padding(.horizontal, 48)
            }
            .padding(.top, 36)
            .padding(.bottom, 32)
        }
    }

    // MARK: – Metadata Strip

    private var metadataStrip: some View {
        HStack(spacing: 0) {
            metaCell(label: "DATE", value: eventDateStr)
            metaDivider
            metaCell(label: "DURATION", value: durationStr)
            metaDivider
            metaCell(label: "SEX", value: data.userProfile.sex.rawValue.capitalized)
            metaDivider
            metaCell(label: "WEIGHT", value: "\(Int(data.userProfile.weightKg)) kg")
            metaDivider
            metaCell(label: "AGE", value: ageStr)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 48)
        .background(NightReportPDFPage.navy.opacity(0.06))
    }

    private func metaCell(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(NightReportPDFPage.inkLight)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(NightReportPDFPage.ink)
        }
        .frame(maxWidth: .infinity)
    }

    private var metaDivider: some View {
        Rectangle()
            .fill(NightReportPDFPage.rule)
            .frame(width: 1, height: 32)
    }

    // MARK: – Gold Rule

    private var goldRulePDF: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [NightReportPDFPage.gold, NightReportPDFPage.gold.opacity(0.25), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .frame(height: 1.5)
            .padding(.horizontal, 48)
    }

    // MARK: – Report Body

    private var reportBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { i, para in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        // Section number
                        Text(i < NightReportPDFPage.sectionNums.count
                             ? NightReportPDFPage.sectionNums[i] : "0\(i + 1)")
                            .font(.system(size: 30, weight: .black, design: .monospaced))
                            .foregroundStyle(NightReportPDFPage.gold.opacity(0.30))
                            .frame(width: 44, alignment: .trailing)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(i < NightReportPDFPage.sectionTitles.count
                                 ? NightReportPDFPage.sectionTitles[i] : "SECTION")
                                .font(.system(size: 9, weight: .black))
                                .tracking(3)
                                .foregroundStyle(NightReportPDFPage.navy)

                            Text(para)
                                .font(.system(size: 14.5, design: .serif))
                                .foregroundStyle(NightReportPDFPage.ink)
                                .lineSpacing(5)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 48)
                .padding(.top, 28)
                .padding(.bottom, 10)

                if i < paragraphs.count - 1 {
                    // Section divider
                    HStack(spacing: 0) {
                        Spacer().frame(width: 48 + 44 + 14) // align with text column
                        Canvas { ctx, size in
                            var path = Path()
                            path.move(to: CGPoint(x: 0, y: 0))
                            path.addLine(to: CGPoint(x: size.width, y: 0))
                            ctx.stroke(
                                path,
                                with: .color(NightReportPDFPage.rule),
                                style: StrokeStyle(lineWidth: 1, dash: [5, 6])
                            )
                        }
                        .frame(height: 1)
                        Spacer().frame(width: 48)
                    }
                    .padding(.top, 14)
                }
            }
        }
        .padding(.bottom, 28)
    }

    // MARK: – Stats Section

    private var statsSection: some View {
        VStack(spacing: 14) {
            Text("NIGHT VITALS")
                .font(.system(size: 9, weight: .black))
                .tracking(3)
                .foregroundStyle(NightReportPDFPage.inkLight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 48)
                .padding(.top, 24)

            HStack(spacing: 1) {
                statCell(
                    value: String(format: "%.3f%%", data.peakBAC),
                    label: "PEAK BAC",
                    icon: "waveform.path.ecg",
                    highlight: data.peakBAC > 0.08
                )
                Rectangle().fill(NightReportPDFPage.rule).frame(width: 1)
                statCell(value: "\(data.drinkCount)", label: "DRINKS", icon: "wineglass.fill", highlight: false)
                Rectangle().fill(NightReportPDFPage.rule).frame(width: 1)
                statCell(value: String(format: "%.1f", data.standardDrinks), label: "STD DRINKS", icon: "drop.fill", highlight: false)
                Rectangle().fill(NightReportPDFPage.rule).frame(width: 1)
                statCell(value: "\(Int(data.calories))", label: "CALORIES", icon: "flame.fill", highlight: false)
                Rectangle().fill(NightReportPDFPage.rule).frame(width: 1)
                statCell(value: "\(data.waterCount)", label: "WATER", icon: "drop.fill", highlight: false)
                Rectangle().fill(NightReportPDFPage.rule).frame(width: 1)
                statCell(value: durationStr, label: "DURATION", icon: "clock.fill", highlight: false)
            }
            .background(.white)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(NightReportPDFPage.rule, lineWidth: 1))
            .padding(.horizontal, 48)
            .padding(.bottom, 24)
        }
    }

    private func statCell(value: String, label: String, icon: String, highlight: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(highlight ? NightReportPDFPage.gold : NightReportPDFPage.inkLight)
            Text(value)
                .font(.system(size: 17, weight: .black, design: .monospaced))
                .foregroundStyle(highlight ? NightReportPDFPage.gold : NightReportPDFPage.ink)
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(NightReportPDFPage.inkLight)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    // MARK: – Footer

    private var pageFooter: some View {
        HStack {
            HStack(spacing: 8) {
                if let icon = UIImage(named: "AppIcon") {
                    Image(uiImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .cornerRadius(4)
                }
                Text("TRACKSIP")
                    .font(.system(size: 8, weight: .black))
                    .tracking(2.5)
                    .foregroundStyle(NightReportPDFPage.inkLight)
            }
            Spacer()
            Text("Generated \(Date(), format: .dateTime.day().month(.abbreviated).year()) · Personal Health Report · Confidential")
                .font(.system(size: 8))
                .foregroundStyle(NightReportPDFPage.inkLight.opacity(0.6))
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 18)
        .background(NightReportPDFPage.navy.opacity(0.06))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(NightReportPDFPage.rule)
                .frame(height: 1)
        }
    }
}
