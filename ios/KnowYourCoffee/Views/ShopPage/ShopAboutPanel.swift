import SwiftUI

/// About tab: update prompt, gear, space, then the record thread.
/// Mirrors web AboutSection: every card is an eyebrow row plus label/pill rows.
/// Beans and Menu are not shown: sellers will manage those from the Shop tab.
struct ShopAboutPanel: View {
    let shop: CoffeeShop
    /// Opens the report launcher; a fact lands on that sheet.
    let onUpdate: (ReportFact?) -> Void

    @State private var showAllRecords = false

    private static let recordPreview = 3

    private var reports: [Report] { shop.reports ?? [] }
    private var reportCount: Int { shop.reportCount ?? reports.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            UpdatePromptRow { onUpdate(nil) }
            gearCard
            spaceCard
            records
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }

    // MARK: Gear

    private var gearCard: some View {
        AboutCard(eyebrow: "Gear") {
            if shop.knownMachines.isEmpty {
                UnknownRow(label: "Espresso machine") { onUpdate(.machine) }
            } else {
                ForEach(Array(shop.knownMachines.enumerated()), id: \.offset) { _, machine in
                    InfoRow(label: machine.display) { Pill(text: "Espresso machine") }
                }
            }
            ForEach(shop.grinders, id: \.self) { grinder in
                InfoRow(label: grinder) { Pill(text: "Grinder") }
            }
        }
    }

    // MARK: Space

    private var spaceCard: some View {
        AboutCard(eyebrow: "Space") {
            amenityRow("Dog friendly", shop.dogFriendly)
            amenityRow("Wi-Fi", shop.wifi)
            amenityRow("Outdoor seating", shop.outdoorSeating)
        }
    }

    @ViewBuilder
    private func amenityRow(_ label: String, _ value: Bool?) -> some View {
        if let value {
            InfoRow(label: label) { Pill(text: value ? "Yes" : "No") }
        } else {
            UnknownRow(label: label) { onUpdate(.space) }
        }
    }

    // MARK: Records

    /// One launcher session saves several one-field reports; show them as one record.
    private var recordGroups: [RecordGroup] { RecordGroup.group(reports) }

    private var visibleGroups: [RecordGroup] {
        showAllRecords ? recordGroups : Array(recordGroups.prefix(Self.recordPreview))
    }

    private var recordsMeta: String? {
        guard let latest = reports.first else { return nil }
        return "\(ShopPageFormat.plural(reportCount, "report")) · latest \(RelativeDate.format(latest.createdAt))"
    }

    private var records: some View {
        VStack(alignment: .leading, spacing: 10) {
            ShopSectionHeader("Records", meta: recordsMeta)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 0) {
                if reports.isEmpty {
                    Text("No records yet. Be the first to report what’s on the bar.")
                        .font(.kycSecondary)
                        .foregroundStyle(Color.inkMuted)
                        .padding(.vertical, 14)
                }
                ForEach(Array(visibleGroups.enumerated()), id: \.element.id) { index, group in
                    if index > 0 { Divider().overlay(Color.cream200) }
                    recordRow(group)
                }
                if recordGroups.count > Self.recordPreview {
                    Divider().overlay(Color.cream200)
                    ShopLinkButton(label: showAllRecords ? "Show fewer" : "See all \(ShopPageFormat.plural(recordGroups.count, "record"))") {
                        withAnimation(.easeOut(duration: 0.2)) { showAllRecords.toggle() }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                }
            }
            .padding(.horizontal, 16)
            .cardStyle()
        }
    }

    private func recordRow(_ group: RecordGroup) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ReporterAvatar(reporter: group.reporter)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(group.reporter?.name ?? "Anonymous").font(.kycMetaBold).foregroundStyle(Color.ink)
                    Text("\(RelativeDate.format(group.createdAt)) · via \(group.source)")
                        .font(.kycMeta)
                        .foregroundStyle(Color.inkMuted)
                }
                Text(group.summary)
                    .font(.kycSecondary)
                    .lineSpacing(3)
                    .foregroundStyle(Color.ink)
            }
        }
        .padding(.vertical, 12)
    }
}

/// Consecutive reports by one reporter within ten minutes, shown as one row.
/// Display only; the server keeps each report.
private struct RecordGroup: Identifiable {
    let id: String
    let reporter: Reporter?
    let createdAt: String
    let source: String
    let summary: String

    private static let window: TimeInterval = 10 * 60

    static func group(_ reports: [Report]) -> [RecordGroup] {
        var runs: [[Report]] = []
        for report in reports {
            if let last = runs.last?.last, joins(report, last) {
                runs[runs.count - 1].append(report)
            } else {
                runs.append([report])
            }
        }
        return runs.map { run in
            let summaries = run.map(\.summary).filter { !$0.isEmpty }
            let sources = Set(run.map { $0.source.lowercased() })
            return RecordGroup(
                id: run[0].id,
                reporter: run[0].reporter,
                createdAt: run[0].createdAt,
                source: sources.count == 1 ? sources.first! : "photo and text",
                summary: summaries.isEmpty ? "Confirmed the current record." : summaries.joined(separator: " · ")
            )
        }
    }

    /// Reports arrive newest first, so `previous` is the later one.
    private static func joins(_ report: Report, _ previous: Report) -> Bool {
        guard let reporter = report.reporter, reporter == previous.reporter,
              let a = RelativeDate.date(report.createdAt),
              let b = RelativeDate.date(previous.createdAt)
        else { return false }
        return abs(b.timeIntervalSince(a)) <= window
    }
}

// MARK: - Pieces

/// Tappable row that opens the report form. A list-row shape instead of a
/// banner with two buttons, which reads as foreign inside an iOS scroll view.
private struct UpdatePromptRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.espresso700)
                    .frame(width: 36, height: 36)
                    .background(Color.cream100, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Report an update")
                        .font(.kycBodyBold)
                        .foregroundStyle(Color.ink)
                    Text("Machine, beans, drinks, or photos")
                        .font(.kycSecondary)
                        .foregroundStyle(Color.inkMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.inkFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cardStyle()
    }
}

// White card: eyebrow row (with an optional card-level note on the right), then rows.
private struct AboutCard<Content: View>: View {
    let eyebrow: String
    var tag: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                EyebrowLabel(eyebrow)
                Spacer(minLength: 8)
                if let tag { EyebrowLabel(tag).multilineTextAlignment(.trailing) }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

/// Label on the left, pills (or a link) right-aligned and wrapping.
private struct InfoRow<Trailing: View>: View {
    let label: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.kycSecondary)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            FlowLayout(spacing: 6, trailing: true) { trailing }
        }
    }
}

/// A detail nobody has reported yet. The trailing control is a real button,
/// outlined so it does not read as one more Pill.
private struct UnknownRow: View {
    let label: String
    let onKnow: () -> Void

    var body: some View {
        InfoRow(label: label) {
            Button(action: onKnow) {
                Label("Add", systemImage: "plus")
                    .font(.kycMetaBold)
                    .foregroundStyle(Color.espresso700)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .overlay(Capsule().stroke(Color.espresso700.opacity(0.45), lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(label)")
        }
    }
}
