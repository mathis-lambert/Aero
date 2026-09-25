import BrowserCore
import Foundation
import SwiftUI

/// Entries visited on one calendar day, newest first.
struct HistoryDay: Identifiable {
    let id: Date
    let entries: [HistoryEntry]

    var title: Text {
        if Calendar.current.isDateInToday(id) { return Text("Today") }
        if Calendar.current.isDateInYesterday(id) { return Text("Yesterday") }
        let includesYear = !Calendar.current.isDate(id, equalTo: .now, toGranularity: .year)
        let style = Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide)
        return Text(id, format: includesYear ? style.year() : style)
    }

    /// Keeps the entries' order; they arrive sorted by their last visit.
    static func group(_ entries: [HistoryEntry]) -> [HistoryDay] {
        var days: [HistoryDay] = []
        var current: (day: Date, entries: [HistoryEntry])?
        for entry in entries {
            let day = Calendar.current.startOfDay(for: entry.lastVisit)
            if current?.day != day {
                if let current { days.append(HistoryDay(id: current.day, entries: current.entries)) }
                current = (day, [])
            }
            current?.entries.append(entry)
        }
        if let current { days.append(HistoryDay(id: current.day, entries: current.entries)) }
        return days
    }
}

enum HistoryClearRange: CaseIterable, Identifiable {
    case lastHour, today, todayAndYesterday, all
    private static let hour: TimeInterval = 60 * 60

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .lastHour: "Last hour"
        case .today: "Today"
        case .todayAndYesterday: "Today and yesterday"
        case .all: "All history"
        }
    }

    /// `nil` clears everything.
    func start(now: Date = .now) -> Date? {
        let today = Calendar.current.startOfDay(for: now)
        switch self {
        case .lastHour: return now.addingTimeInterval(-Self.hour)
        case .today: return today
        case .todayAndYesterday: return Calendar.current.date(byAdding: .day, value: -1, to: today)
        case .all: return nil
        }
    }
}
