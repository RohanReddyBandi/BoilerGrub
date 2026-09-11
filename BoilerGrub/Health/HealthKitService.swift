import Foundation
import HealthKit
import OSLog

/// The app's only point of contact with HealthKit.
///
/// Two rules shape this class, both from the brief:
///
/// 1. **Permission is handled once.** Authorisation is requested the first time
///    the reader actually tries to save something, not at launch — asking for
///    health access before showing a single menu is how apps get denied.
/// 2. **Denial cannot break anything else.** Nothing in the app awaits a
///    HealthKit result in order to function. The plate is written to SwiftData
///    first and Health is attempted second, so a refusal, a restriction, or an
///    iPad with no Health app costs the reader nothing but the sync.
///
/// The app requests **write access only**. It never reads the reader's health
/// data — the daily view is built from what BoilerGrub itself logged.
@Observable
@MainActor
final class HealthKitService {

    enum Authorization: Equatable {
        /// No Health data on this device at all.
        case unavailable
        case notDetermined
        case authorized
        /// The reader declined, or the device is restricted by policy.
        case denied
    }

    enum SaveError: LocalizedError {
        case unavailable
        case denied
        case nothingToSave
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .unavailable: "Apple Health isn't available on this device."
            case .denied: "BoilerGrub doesn't have permission to write to Apple Health."
            case .nothingToSave: "This plate has no nutrition to save."
            case .failed(let reason): reason
            }
        }

        var recoveryHint: String? {
            switch self {
            case .denied: "You can turn this on in Settings → Health → Data Access & Devices → BoilerGrub. Your plate is saved in BoilerGrub either way."
            case .unavailable: "Your plate is still saved in BoilerGrub."
            case .nothingToSave, .failed: "Your plate is saved in BoilerGrub — you can retry the Health sync from the daily view."
            }
        }
    }

    private let store = HKHealthStore()
    private let logger = Logger(subsystem: "com.rohanreddybandi.BoilerGrub", category: "Health")

    private(set) var authorization: Authorization

    /// The four quantity types the brief calls for, plus the food correlation
    /// that groups them into a single entry in the Health app.
    private static let energy = HKQuantityType(.dietaryEnergyConsumed)
    private static let protein = HKQuantityType(.dietaryProtein)
    private static let carbs = HKQuantityType(.dietaryCarbohydrates)
    private static let fat = HKQuantityType(.dietaryFatTotal)
    private static let food = HKCorrelationType(.food)

    private static var shareTypes: Set<HKSampleType> {
        [energy, protein, carbs, fat, food]
    }

    init() {
        authorization = HKHealthStore.isHealthDataAvailable() ? .notDetermined : .unavailable
        refreshAuthorization()
    }

    // MARK: - Permission

    /// Reads the current status without prompting. HealthKit deliberately never
    /// reveals *read* status; since this app only writes, the status it does
    /// report is meaningful.
    func refreshAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorization = .unavailable
            return
        }
        let statuses = Self.shareTypes.map { store.authorizationStatus(for: $0) }
        if statuses.contains(where: { $0 == .sharingAuthorized }) {
            authorization = .authorized
        } else if statuses.allSatisfy({ $0 == .sharingDenied }) {
            authorization = .denied
        } else {
            authorization = .notDetermined
        }
    }

    /// Prompts once. Calling it again after the reader has answered is a no-op
    /// as far as they can see — iOS won't show the sheet a second time.
    @discardableResult
    func requestAuthorization() async -> Authorization {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorization = .unavailable
            return authorization
        }
        do {
            try await store.requestAuthorization(toShare: Self.shareTypes, read: [])
        } catch {
            // A thrown error here means the prompt itself failed, which is not
            // the same as the reader saying no. Fall through to the status read.
            logger.warning("authorization request failed: \(error.localizedDescription, privacy: .public)")
        }
        refreshAuthorization()
        return authorization
    }

    // MARK: - Writing

    /// Saves one plate to Health as a set of food entries — one per plate item,
    /// so the Health app shows "Chicken Tikka Masala" rather than an anonymous
    /// lump of calories.
    ///
    /// Returns the UUIDs of the saved correlations so the caller can record that
    /// the plate synced.
    @discardableResult
    func save(_ plate: PlateSnapshot) async throws -> [UUID] {
        guard HKHealthStore.isHealthDataAvailable() else { throw SaveError.unavailable }

        if authorization == .notDetermined {
            await requestAuthorization()
        }
        guard authorization != .denied else { throw SaveError.denied }

        let correlations = plate.entries.compactMap { makeCorrelation(for: $0, at: plate.loggedAt) }
        guard !correlations.isEmpty else { throw SaveError.nothingToSave }

        do {
            try await store.save(correlations)
        } catch {
            logger.error("health save failed: \(error.localizedDescription, privacy: .public)")
            // HealthKit reports a refused write as an authorization error rather
            // than throwing at request time, so re-check before blaming the save.
            refreshAuthorization()
            if authorization == .denied { throw SaveError.denied }
            throw SaveError.failed(error.localizedDescription)
        }

        return correlations.map(\.uuid)
    }

    private func makeCorrelation(for entry: PlateSnapshot.Entry, at date: Date) -> HKCorrelation? {
        let facts = entry.totals
        var samples: Set<HKSample> = []

        func add(_ type: HKQuantityType, _ unit: HKUnit, _ value: Double) {
            // HealthKit rejects negatives, and a zero-gram sample is noise in
            // the reader's Health charts rather than information.
            guard value > 0 else { return }
            samples.insert(
                HKQuantitySample(
                    type: type,
                    quantity: HKQuantity(unit: unit, doubleValue: value),
                    start: date,
                    end: date
                )
            )
        }

        add(Self.energy, .kilocalorie(), facts.calories)
        add(Self.protein, .gram(), facts.proteinGrams)
        add(Self.carbs, .gram(), facts.carbGrams)
        add(Self.fat, .gram(), facts.fatGrams)

        guard !samples.isEmpty else { return nil }

        var metadata: [String: Any] = [HKMetadataKeyFoodType: entry.name]
        if let serving = entry.servingSize {
            // The API has no numeric serving weight anywhere — only free text
            // like "1/2 Cup" or "8x10 Cut Serving" — so the reader's own serving
            // count and the court's wording are recorded as plain metadata
            // rather than being guessed into grams.
            metadata["BoilerGrubServing"] = "\(Figure.servings(entry.servings)) × \(serving)"
        }
        metadata["BoilerGrubSource"] = entry.courtName

        return HKCorrelation(type: Self.food, start: date, end: date, objects: samples, metadata: metadata)
    }
}

/// A plain value snapshot of a plate, so the Health service never has to reach
/// into SwiftData or the live plate object.
struct PlateSnapshot: Sendable {
    struct Entry: Sendable {
        let name: String
        let servings: Double
        let servingSize: String?
        let courtName: String
        /// Already multiplied by the serving count.
        let totals: NutritionFacts
    }

    let loggedAt: Date
    let entries: [Entry]
}
