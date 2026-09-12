import SwiftUI

/// A single quiet line: previous day, the date, next day.
///
/// This replaced a full-width scrolling strip of day stubs. Choosing a date is
/// something you do occasionally — usually you want today — so it shouldn't own
/// a third of the screen above the menu. Tapping the date opens a real picker
/// for jumping somewhere distant, which keeps the capability without the
/// footprint.
struct DateBar: View {
    @Binding var day: CalendarDay
    @State private var showingPicker = false

    var body: some View {
        HStack(spacing: 0) {
            arrow("chevron.left", accessibility: "Previous day") {
                day = day.adding(days: -1)
            }

            Button { showingPicker = true } label: {
                HStack(spacing: 7) {
                    StampLabel(label, color: Palette.muted, font: Type.label)
                    if !day.isToday {
                        Circle().fill(Palette.gold).frame(width: 3, height: 3)
                    }
                }
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Opens a date picker")

            arrow("chevron.right", accessibility: "Next day") {
                day = day.adding(days: 1)
            }

            Spacer(minLength: 0)

            if !day.isToday {
                Button { withAnimation(.snappy) { day = .today } } label: {
                    StampLabel("today", color: Palette.gold, font: Type.micro)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showingPicker) {
            DayPickerSheet(day: $day)
        }
    }

    private var label: String {
        guard let date = day.date else { return "" }
        if day.isToday { return "today" }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private var accessibilityLabel: String {
        let full = day.date?.formatted(.dateTime.weekday(.wide).month(.wide).day()) ?? ""
        return day.isToday ? "Today, \(full)" : full
    }

    private func arrow(_ symbol: String, accessibility: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.faint)
                .frame(width: 28, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
    }
}

private struct DayPickerSheet: View {
    @Binding var day: CalendarDay
    @Environment(\.dismiss) private var dismiss
    @State private var selection = Date()

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "pick a day", onClose: { dismiss() }) { EmptyView() }

            DatePicker("Day", selection: $selection, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(Palette.gold)
                .padding(.horizontal, 14)
                .padding(.top, 8)

            Spacer(minLength: 0)

            TicketButton(title: "show this day", emphasised: true) {
                day = CalendarDay(selection)
                dismiss()
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 12)
        }
        .background(Palette.ground)
        .onAppear { selection = day.date ?? Date() }
        .presentationDetents([.medium, .large])
        .presentationBackground(Palette.ground)
    }
}
