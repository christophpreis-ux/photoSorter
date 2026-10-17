import SwiftUI

/// Auswahl eines Jahres/Monats aus der Apple-Fotos-Mediathek.
struct PhotosSourcePicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var authorized = PhotosLibrary.isAuthorized
    @State private var years: [Int] = []
    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var month = 0
    @State private var count: Int?
    @State private var allowNetwork = PhotosLibrary.allowNetworkAccess

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading) {
                    Text("Apple Fotos durchsuchen").font(.title2.bold())
                    Text("Wähle einen Zeitraum – PhotoSorter analysiert alle Fotos darin und schlägt vor, was weg kann.")
                        .foregroundStyle(.secondary)
                }
            }

            if !authorized {
                Label("PhotoSorter braucht Zugriff auf deine Fotos-Mediathek.", systemImage: "lock.fill")
                Button("Zugriff erlauben") {
                    Task {
                        authorized = await PhotosLibrary.requestAuthorization()
                        if authorized { load() }
                    }
                }
                .buttonStyle(.glassProminent)
            } else {
                Form {
                    Picker("Jahr", selection: $year) {
                        ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                    }
                    Picker("Monat", selection: $month) {
                        Text("Ganzes Jahr").tag(0)
                        ForEach(1...12, id: \.self) { Text(Calendar.current.standaloneMonthSymbols[$0 - 1]).tag($0) }
                    }
                    Toggle("Fotos aus iCloud laden, falls nicht lokal", isOn: $allowNetwork)
                    LabeledContent("Fotos im Zeitraum") {
                        Text(count.map { $0.formatted() } ?? "…").monospacedDigit()
                    }
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
                .frame(height: 230)

                VStack(alignment: .leading, spacing: 6) {
                    Label("Favoriten werden immer behalten.", systemImage: "heart.fill")
                        .foregroundStyle(.pink)
                    Label("Aussortierte Fotos landen in „Zuletzt gelöscht“ und sind dort 30 Tage wiederherstellbar.",
                          systemImage: "trash")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }

            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                Button("Analysieren") {
                    PhotosLibrary.allowNetworkAccess = allowNetwork
                    model.openPhotos(year: year, month: month == 0 ? nil : month)
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!authorized || (count ?? 0) == 0)
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(Theme.background)
        .task {
            if !authorized, PhotosLibrary.isAuthorized { authorized = true }
            if authorized { load() }
        }
        .onChange(of: year) { updateCount() }
        .onChange(of: month) { updateCount() }
    }

    private func load() {
        years = PhotosLibrary.availableYears()
        if let first = years.first, !years.contains(year) { year = first }
        updateCount()
    }

    private func updateCount() {
        count = nil
        let year = year, month = month == 0 ? nil : month
        Task.detached {
            let value = PhotosLibrary.count(year: year, month: month)
            await MainActor.run { count = value }
        }
    }
}
