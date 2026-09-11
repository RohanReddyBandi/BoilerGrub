import SwiftUI

/// The running tab, pinned under the menu.
///
/// It appears only once there's something on the plate, so the menu screen is
/// uncluttered until the reader starts building — and once it's there, the
/// calorie figure is always in view while they browse.
struct TrayBar: View {
    @Environment(Plate.self) private var plate
    let onOpen: () -> Void

    var body: some View {
        if !plate.isEmpty {
            let totals = plate.totals

            Button(action: onOpen) {
                VStack(spacing: 0) {
                    Perforation()

                    HStack(alignment: .lastTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            StampLabel("on your plate", color: Palette.gold)
                            StampLabel(
                                "\(plate.itemCount) item\(plate.itemCount == 1 ? "" : "s")",
                                color: Palette.muted,
                                font: Type.micro
                            )
                        }

                        Spacer(minLength: 8)

                        Text(Figure.calories(totals.calories))
                            .font(.system(size: 30, weight: .light, design: .monospaced))
                            .foregroundStyle(Palette.bone)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)

                        StampLabel("kcal", color: Palette.muted, font: Type.micro)

                        Image(systemName: "chevron.up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.gold)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 14)
                    .padding(.bottom, 6)
                }
                .background(Palette.ground)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Your plate: \(plate.itemCount) items, \(Figure.calories(plate.totals.calories)) calories")
            .accessibilityHint("Opens the plate")
        }
    }
}
