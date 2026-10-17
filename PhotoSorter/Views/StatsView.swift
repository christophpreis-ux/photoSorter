import SwiftUI
import SwiftData
import Charts

/// Statistik aus der lokalen Datenbank: wie viel bisher aussortiert wurde.
struct StatsView: View {
    @Query(sort: \SortRecord.date, order: .reverse) private var records: [SortRecord]
    @Query(sort: \MergeRecord.date, order: .reverse) private var merges: [MergeRecord]

    var body: some View {
        let analyzed = records.reduce(0) { $0 + $1.analyzed }
        let rejected = records.reduce(0) { $0 + $1.rejected }
        let bytes = records.reduce(Int64(0)) { $0 + $1.rejectedBytes }
        let favorites = records.reduce(0) { $0 + $1.protectedFavorites }

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Image(systemName: "chart.bar.xaxis").font(.title).foregroundStyle(Theme.accent)
                    Text("Statistik").font(.largeTitle.bold())
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                    StatTile(title: "Aussortiert", value: rejected.formatted(), symbol: "xmark.bin.fill", color: Theme.reject)
                    StatTile(title: "Analysiert", value: analyzed.formatted(), symbol: "sparkle.magnifyingglass", color: Theme.accent)
                    StatTile(title: "Aussortier-Quote", value: analyzed > 0 ? (Double(rejected) / Double(analyzed)).formatted(.percent.precision(.fractionLength(0))) : "–",
                             symbol: "percent", color: .orange)
                    StatTile(title: "Datenmenge aussortiert", value: bytes > 0 ? ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) : "–",
                             symbol: "internaldrive.fill", color: .purple)
                    StatTile(title: "Kombinierte Gruppenfotos", value: merges.count.formatted(), symbol: "wand.and.stars", color: Theme.keep)
                    StatTile(title: "Geschützte Favoriten", value: favorites.formatted(), symbol: "heart.fill", color: .pink)
                }

                if !records.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Pro Monat").font(.title3.bold())
                        Chart {
                            ForEach(records) { record in
                                BarMark(x: .value("Monat", record.date, unit: .month), y: .value("Fotos", record.rejected))
                                    .foregroundStyle(by: .value("Art", "Aussortiert"))
                                BarMark(x: .value("Monat", record.date, unit: .month), y: .value("Fotos", record.kept))
                                    .foregroundStyle(by: .value("Art", "Behalten"))
                            }
                        }
                        .chartForegroundStyleScale(["Aussortiert": Theme.reject, "Behalten": Theme.keep])
                        .frame(height: 220)
                    }
                    .padding(16)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Verlauf").font(.title3.bold())
                        ForEach(records) { record in
                            HStack {
                                Image(systemName: record.sourceKind == "Apple Fotos" ? "photo.on.rectangle.angled" : "folder.fill")
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 22)
                                VStack(alignment: .leading) {
                                    Text(record.sourceName).lineLimit(1)
                                    Text(record.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(record.rejected) von \(record.analyzed) aussortiert")
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                            Divider()
                        }
                    }
                    .padding(16)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                } else {
                    ContentUnavailableView("Noch keine Daten", systemImage: "chart.bar",
                                           description: Text("Sobald du Fotos sortierst, erscheinen hier deine Statistiken."))
                }
            }
            .padding(24)
        }
        .background(Theme.background)
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).font(.title2).foregroundStyle(color)
            Text(value).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
            Text(title).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular.tint(color.opacity(0.08)), in: .rect(cornerRadius: 18))
    }
}
