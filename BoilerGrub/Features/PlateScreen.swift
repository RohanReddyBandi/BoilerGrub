import SwiftUI
import SwiftData

/// The plate, printed as a register tape: a line per item, a double rule, then
/// the total.
struct PlateScreen: View {
    @Environment(Plate.self) private var plate
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var saveState: SaveState = .idle
    @State private var notice: SaveNotice?

    private enum SaveState { case idle, saving }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if plate.isEmpty {
                        TicketNotice(
                            label: "empty",
                            title: "Nothing on your plate yet.",
                            detail: "Tap a dish on the menu to see its macros and add it."
                        ) { EmptyView() }
                    } else {
                        ForEach(plate.entries) { entry in
                            PlateRow(entry: entry)
                            HairlineRule(color: Palette.faint.opacity(0.35))
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(Palette.ground)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                SheetHeader(title: "your plate", onClose: { dismiss() }) {
                    if !plate.isEmpty {
                        Button { plate.clear() } label: {
                            StampLabel("clear", color: Palette.muted, font: Type.micro)
                                .padding(.leading, 16)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !plate.isEmpty {
                    SaveBar(totals: plate.totals, isSaving: saveState == .saving) { await save() }
                }
            }
        }
        .alert(item: $notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK")) { dismiss() }
            )
        }
    }

    /// Local first, Health second.
    ///
    /// The SwiftData write is what the reader actually asked for; the Health
    /// sync is a bonus that can fail for reasons entirely outside their control
    /// — a denied permission, an iPad, a restriction. Saving locally first means
    /// none of those can lose their plate.
    private func save() async {
        saveState = .saving
        defer { saveState = .idle }

        let snapshot = plate.snapshot()
        let record = LoggedPlate(
            loggedAt: snapshot.loggedAt,
            courtName: plate.entries.first?.courtName ?? "",
            mealName: plate.entries.first?.mealName
        )
        context.insert(record)
        for (index, entry) in plate.entries.enumerated() {
            let item = LoggedItem(
                itemID: entry.detail.id,
                name: entry.detail.name,
                servings: entry.servings,
                servingSize: entry.perServing.servingSize,
                position: index,
                perServing: entry.perServing
            )
            item.plate = record
            context.insert(item)
        }

        do {
            try context.save()
        } catch {
            notice = SaveNotice(
                title: "Couldn't save your plate",
                message: "Something went wrong writing to this device. Your plate is still here — try again."
            )
            return
        }

        // From here on the plate is safely recorded; anything below only affects
        // whether it also reaches Health.
        do {
            let ids = try await services.health.save(snapshot)
            record.healthSampleIDs = ids.map(\.uuidString)
            record.syncState = .synced
            try? context.save()
            plate.clear()
            dismiss()
        } catch let error as HealthKitService.SaveError {
            record.syncState = error.isDeclined ? .declined : .failed
            try? context.save()
            plate.clear()
            notice = SaveNotice(
                title: "Saved to BoilerGrub",
                message: [error.errorDescription, error.recoveryHint]
                    .compactMap { $0 }.joined(separator: " ")
            )
        } catch {
            record.syncState = .failed
            try? context.save()
            plate.clear()
            notice = SaveNotice(
                title: "Saved to BoilerGrub",
                message: "Your plate is logged, but it didn't reach Apple Health. You can retry from today's log."
            )
        }
    }
}

struct SaveNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

extension HealthKitService.SaveError {
    var isDeclined: Bool {
        if case .denied = self { return true }
        return false
    }
}

// MARK: - Rows

private struct PlateRow: View {
    let entry: Plate.Entry
    @Environment(Plate.self) private var plate

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TicketRow {
                Text(entry.detail.name)
                    .font(Type.dish)
                    .foregroundStyle(Palette.bone)
                    .multilineTextAlignment(.leading)
            } trailing: {
                Text(Figure.calories(entry.totals.calories))
                    .font(Type.figureRow)
                    .foregroundStyle(Palette.bone)
                    .monospacedDigit()
            }

            HStack(spacing: 14) {
                ServingStepper(
                    servings: Binding(
                        get: { entry.servings },
                        set: { plate.setServings($0, for: entry.id) }
                    )
                )

                if let serving = entry.perServing.servingSize {
                    StampLabel("× \(serving)", color: Palette.muted, font: Type.micro)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Button {
                    plate.remove(entry.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.faint)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(entry.detail.name)")
            }

            MacroLine(facts: entry.totals)
        }
        .padding(.vertical, 18)
    }
}

/// The per-row macro breakdown, kept to one quiet line so the calorie figure at
/// the end of the leader dots stays the row's headline.
struct MacroLine: View {
    let facts: NutritionFacts

    var body: some View {
        HStack(spacing: 16) {
            part("p", facts.proteinGrams)
            part("c", facts.carbGrams)
            part("f", facts.fatGrams)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(Figure.grams(facts.proteinGrams)) grams protein, "
            + "\(Figure.grams(facts.carbGrams)) grams carbohydrates, "
            + "\(Figure.grams(facts.fatGrams)) grams fat"
        )
    }

    private func part(_ letter: String, _ grams: Double) -> some View {
        HStack(spacing: 4) {
            StampLabel(letter, color: Palette.gold, font: Type.micro)
            Text(Figure.grams(grams) + "g")
                .font(Type.figureSmall)
                .foregroundStyle(Palette.muted)
                .monospacedDigit()
        }
    }
}

/// The total lives in the pinned footer rather than at the end of the scroll.
/// A register tape prints the total last, but a plate you are still editing is
/// one you need the running figure for at all times — so the tape's ending is
/// pinned to the bottom of the screen instead of the bottom of the list.
private struct SaveBar: View {
    let totals: NutritionFacts
    let isSaving: Bool
    let action: () async -> Void

    var body: some View {
        VStack(spacing: 0) {
            Perforation()

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    StampLabel("total", color: Palette.gold, font: Type.labelLarge)
                    Spacer()
                    Text(Figure.calories(totals.calories))
                        .font(Type.figureTotal)
                        .foregroundStyle(Palette.goldBright)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    StampLabel("kcal", color: Palette.muted, font: Type.micro)
                }
                .padding(.top, 14)

                MacroLine(facts: totals).padding(.top, 10)
            }
            .padding(.horizontal, 22)
            .accessibilityElement(children: .contain)

            Button {
                Task { await action() }
            } label: {
                HStack(spacing: 9) {
                    if isSaving {
                        ProgressView().tint(Palette.ground).scaleEffect(0.75)
                    }
                    StampLabel(isSaving ? "saving" : "save to apple health",
                               color: Palette.ground, font: Type.labelLarge)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Palette.gold)
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 6)
        }
        .background(Palette.ground)
    }
}

#Preview {
    PlateScreen()
        .environment(AppServices.preview())
        .environment(Plate())
        .modelContainer(for: [LoggedPlate.self, LoggedItem.self], inMemory: true)
}
