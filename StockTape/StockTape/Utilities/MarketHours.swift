//
//  MarketHours.swift
//  StockTape
//
//  Determines whether the US equity market is open and, from that, how often
//  StockTape should refresh. All calculations use US Eastern time.
//
//  v1 limitation: market holidays are NOT accounted for. On a holiday the app
//  will still treat 09:30–16:00 ET Mon–Fri as "open" and refresh on the faster
//  cadence. This is acceptable for v1 and documented in the README.
//

import Foundation

enum MarketHours {

    private static let easternTimeZone = TimeZone(identifier: "America/New_York")!

    private static var easternCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = easternTimeZone
        return calendar
    }

    /// True Monday–Friday between 09:30 and 16:00 US Eastern time.
    static func isMarketOpen(at date: Date = Date()) -> Bool {
        let calendar = easternCalendar
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)

        guard let weekday = components.weekday,
              let hour = components.hour,
              let minute = components.minute
        else { return false }

        // Calendar weekday: 1 = Sunday ... 7 = Saturday.
        guard (2...6).contains(weekday) else { return false }

        let minutesIntoDay = hour * 60 + minute
        let open = 9 * 60 + 30   // 09:30
        let close = 16 * 60      // 16:00
        return minutesIntoDay >= open && minutesIntoDay < close
    }

    /// Faster cadence while open, slower while closed.
    static func refreshInterval(at date: Date = Date()) -> TimeInterval {
        isMarketOpen(at: date)
            ? Constants.marketRefreshInterval
            : Constants.offHoursRefreshInterval
    }
}
