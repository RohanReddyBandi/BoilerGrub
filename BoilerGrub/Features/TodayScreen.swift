import SwiftUI
import SwiftData

/// Everything logged today, newest first, with the day's running totals at the
/// top — the same tape treatment as the plate, one level up.
struct TodayScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var plates: [LoggedPlate]
    @State private var retrying: PersistentIdentifier?

    init() {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        _plates = Query(
            filter: #Predicate<LoggedPlate> { $0.loggedAt >= startOfDay },
            sort: \LoggedPlate.loggedAt,
            order: .reverse
        )
    }

    private var dayTotals: NutritionFacts {
        plates.reduce(NutritionFacts.zero) { $0 + $1.totals }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if plates.isEmpty {
                        TicketNotice(
                            label: "nothing yet",
                            title: "You haven't logged anything today.",
                            detail: "Build a plate from any dining court menu and save it — it'll show up here and in Apple Health."
                        ) { EmptyView() }
                    } else {
                        DayTotals(totals: dayTotals, plateCount: plates.count)

                        ForEach(plates) { plate in
                            LoggedPlateBlock(
                                plate: plate,
                                isRetrying: retrying == plate.persistentModelID,
                                onRetry: { await retrySync(plate) },
                                onDelete: { delete(plate) }
                            )
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background(Palette.ground)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                SheetHeader(title: "today", onClose: { dismiss() }) { EmptyView() }
            }
        }
    }

    /// Re-attempts a Health write for a plate that failed or was logged before
    /// permission was granted. The local record is already safe either way.
    private func retrySync(_ plate: LoggedPlate) async {
        retrying = plate.persistentModelID
        defer { retrying = nil }
        do {
            let ids = try await services.health.save(plate.snapshot())
            plate.healthSampleIDs = ids.map(\.uuidString)
            plate.syncState = .synced
        } catch let error as HealthKitService.SaveError {
            plate.syncState = error.isDeclined ? .declined : .failed
        } catch {
            plate.syncState = .failed
        }
        try? context.save()
    }

    private func delete(_ plate: LoggedPlate) {
        // Only the local record is removed. Anything already written to Health
        // belongs to the reader and is theirs to manage in the Health app —
        // silently deleting their health data from under them would be worse
        // than leaving a duplicate.
        context.delete(plate)
        try? context.save()
    }
}

private struct DayTotals: View {
    let totals: NutritionFacts
    let plateCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StampLabel(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()),
                       color: Palette.muted)
                .padding(.top, 22)

            DoubleRule().padding(.top, 18)

            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Text(Figure.calories(totals.calories))
                    .font(Type.figureHero)
                    .foregroundStyle(Palette.bone)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                StampLabel("kcal today", color: Palette.muted, font: Type.labelLarge)
                    .padding(.bottom, 12)
            }
            .padding(.top, 16)

            HairlineRule().padding(.top, 6)

            HStack {
                MacroLine(facts: totals)
                Spacer()
                StampLabel("\(plateCount) plate\(plateCount == 1 ? "" : "s")",
                           color: Palette.faint, font: Type.micro)
            }
            .padding(.top, 16)

            Perforation().padding(.top, 26)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct LoggedPlateBlock: View {
    let plate: LoggedPlate
    let isRetrying: Bool
    let onRetry: () async -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            TickRail()

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    StampLabel(plate.loggedAt.formatted(date: .omitted, time: .shortened),
                               color: Palette.gold)
                    if !plate.courtName.isEmpty {
                        StampLabel("· \(plate.courtName)", color: Palette.muted, font: Type.micro)
                    }
                    Spacer(minLength: 0)
                    SyncBadge(state: plate.syncState)
                }
                .padding(.bottom, 14)

                ForEach(plate.orderedItems) { item in
                    LeaderRow {
                        Text(item.name)
                            .font(Type.dish)
                            .foregroundStyle(Palette.bone)
                            .multilineTextAlignment(.leading)
                    } trailing: {
                        HStack(spacing: 8) {
                            if item.servings != 1 {
                                Text("×\(Figure.servings(item.servings))")
                                    .font(Type.figureSmall)
                                    .foregroundStyle(Palette.muted)
                                    .monospacedDigit()
                            }
                            Text(Figure.calories(item.totalCalories))
                                .font(Type.figureRow)
                                .foregroundStyle(Palette.bone)
                                .monospacedDigit()
                        }
                    }
                    .padding(.vertical, 9)
                    .accessibilityElement(children: .combine)
                }

                HairlineRule().padding(.top, 10)

                HStack {
                    MacroLine(facts: plate.totals)
                    Spacer()
                    Text(Figure.calories(plate.calories))
                        .font(Type.figureRow)
                        .foregroundStyle(Palette.gold)
                        .monospacedDigit()
                }
                .padding(.top, 14)

                HStack(spacing: 18) {
                    if plate.syncState != .synced {
                        Button {
                            Task { await onRetry() }
                        } label: {
                            StampLabel(isRetrying ? "syncing" : "sync to health",
                                       color: Palette.gold, font: Type.micro)
                        }
                        .buttonStyle(.plain)
                        .disabled(isRetrying)
                    }
                    Spacer()
                    Button(role: .destructive, action: onDelete) {
                        StampLabel("delete", color: Palette.faint, font: Type.micro)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 16)
            }
        }
        .padding(.bottom, 34)
    }
}

private struct SyncBadge: View {
    let state: HealthSyncState

    var body: some View {
        switch state {
        case .synced:
            StampLabel("in health", color: Palette.gold, font: Type.micro)
        case .failed:
            StampLabel("not synced", color: Palette.ember, font: Type.micro)
        case .declined:
            StampLabel("health off", color: Palette.faint, font: Type.micro)
        case .notSynced:
            EmptyView()
        }
    }
}

#Preview {
    TodayScreen()
        .environment(AppServices.preview())
        .modelContainer(for: [LoggedPlate.self, LoggedItem.self], inMemory: true)
}
