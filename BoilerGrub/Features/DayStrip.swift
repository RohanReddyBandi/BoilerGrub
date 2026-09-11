import SwiftUI

/// A run of tear-off day stubs. The selected day is marked by a gold rule
/// beneath it — the same underline device the meal selector uses, so the two
/// rows of choices read as one system.
struct DayStrip: View {
    @Binding var day: CalendarDay

    /// A fortnight centred on today. Past days are worth having because their
    /// menus are cached permanently and load instantly; the far future is not,
    /// because the courts haven't posted it.
    private let range = -7...7

    private var days: [CalendarDay] {
        range.map { CalendarDay.today.adding(days: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                StampLabel(monthLabel, color: Palette.muted)
                Spacer()
                if !day.isToday {
                    Button("jump to today") { withAnimation(.snappy) { day = .today } }
                        .font(Type.micro)
                        .tracking(1.1)
                        .foregroundStyle(Palette.gold)
                }
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(days, id: \.self) { candidate in
                            DayStub(day: candidate, isSelected: candidate == day)
                                .id(candidate)
                                .onTapGesture { day = candidate }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .onAppear { proxy.scrollTo(day, anchor: .center) }
                .onChange(of: day) { _, new in
                    withAnimation(.snappy) { proxy.scrollTo(new, anchor: .center) }
                }
            }
        }
        .padding(.top, 22)
    }

    private var monthLabel: String {
        guard let date = day.date else { return "" }
        return date.formatted(.dateTime.month(.wide).year())
    }
}

private struct DayStub: View {
    let day: CalendarDay
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            StampLabel(weekday, color: isSelected ? Palette.gold : Palette.faint, font: Type.micro)

            Text(dayNumber)
                .font(.system(size: 19, weight: isSelected ? .medium : .light, design: .monospaced))
                .foregroundStyle(isSelected ? Palette.bone : Palette.muted)

            Rectangle()
                .fill(isSelected ? Palette.gold : .clear)
                .frame(height: 1.5)
        }
        .frame(width: 46)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            // Today keeps a faint tick even when another day is selected, so the
            // reader never loses their anchor while scrubbing the strip.
            if day.isToday && !isSelected {
                Circle().fill(Palette.gold).frame(width: 3, height: 3).offset(y: -4)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var weekday: String {
        day.date?.formatted(.dateTime.weekday(.abbreviated)) ?? ""
    }

    private var dayNumber: String {
        String(day.day)
    }

    private var accessibilityLabel: String {
        let full = day.date?.formatted(.dateTime.weekday(.wide).month(.wide).day()) ?? ""
        return day.isToday ? "Today, \(full)" : full
    }
}
