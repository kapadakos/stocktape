//
//  Constants.swift
//  StockTape
//
//  All tunable values live here so they can be adjusted in one place.
//

import Foundation
import AppKit

enum Constants {

    // MARK: - Marquee

    /// Fixed width (points) of the status-item button. Keeping it constant
    /// prevents the menu bar from reflowing as the ticker changes.
    static let marqueeVisibleWidth: CGFloat = 160

    /// Scroll speed in points per second.
    static let marqueeScrollSpeed: CGFloat = 40

    /// Separator drawn between position segments.
    static let separatorString = "   ·   "

    /// Font size used for the menu bar status item title.
    static let menuBarFontSize: CGFloat = 11

    // MARK: - Refresh scheduling

    /// Refresh cadence while the US market is open (5 minutes).
    static let marketRefreshInterval: TimeInterval = 300

    /// Refresh cadence outside of market hours (60 minutes).
    static let offHoursRefreshInterval: TimeInterval = 3600

    /// Rebuild the dropdown from a live fetch if the cache is older than this.
    static let cacheStalenessInterval: TimeInterval = 30

    // MARK: - Auth

    /// Refresh the access token if it expires within this window.
    static let tokenExpiryBuffer: TimeInterval = 60

    /// Seconds to back off after receiving an HTTP 429.
    static let rateLimitBackoff: TimeInterval = 60

    // MARK: - Logging

    /// Rotate (truncate) the log file once it grows beyond this size.
    static let logMaxBytes: Int = 512_000

    /// Number of trailing lines kept when the log is rotated.
    static let logRotationKeepLines: Int = 200

    // MARK: - Keychain

    static let keychainService = "com.stocktape.app"

    // MARK: - OAuth endpoints

    static let authorizationURL = "https://api.schwabapi.com/v1/oauth/authorize"
    static let tokenURL = "https://api.schwabapi.com/v1/oauth/token"
    static let redirectURI = "https://127.0.0.1"
    static let oauthScope = "readonly"

    /// Port used by the local loopback callback server (fallback path).
    static let callbackServerPort: UInt16 = 8182

    // MARK: - Schwab API endpoints

    static let accountNumbersURL = "https://api.schwabapi.com/trader/v1/accounts/accountNumbers"
    static let accountsBaseURL = "https://api.schwabapi.com/trader/v1/accounts"
    static let quotesURL = "https://api.schwabapi.com/marketdata/v1/quotes"

    // MARK: - Colors

    /// Green used for positive change.
    static let upColor = NSColor(red: 0.18, green: 0.82, blue: 0.35, alpha: 1.0)

    /// Red used for negative change.
    static let downColor = NSColor(red: 1.0, green: 0.27, blue: 0.23, alpha: 1.0)

    /// Color used for flat (unchanged) positions.
    static let flatColor = NSColor.secondaryLabelColor

    /// Color used for the separator glyph.
    static let separatorColor = NSColor.tertiaryLabelColor
}

// MARK: - User-tunable settings

/// User-adjustable ticker settings, persisted in `UserDefaults`. Falls back to
/// the `Constants` defaults on first launch. Read live every frame so slider
/// changes take effect immediately.
enum TickerSettings {

    private static let defaults = UserDefaults.standard
    private static let speedKey = "marqueeScrollSpeed"
    private static let widthKey = "marqueeVisibleWidth"

    // Allowed slider ranges.
    static let minScrollSpeed: CGFloat = 10
    static let maxScrollSpeed: CGFloat = 120
    static let minVisibleWidth: CGFloat = 60
    static let maxVisibleWidth: CGFloat = 360

    /// Scroll speed in points per second.
    static var scrollSpeed: CGFloat {
        get {
            guard let value = defaults.object(forKey: speedKey) as? Double else {
                return Constants.marqueeScrollSpeed
            }
            return CGFloat(value).clamped(minScrollSpeed, maxScrollSpeed)
        }
        set { defaults.set(Double(newValue.clamped(minScrollSpeed, maxScrollSpeed)), forKey: speedKey) }
    }

    /// Fixed width (points) of the status-item ticker window.
    static var visibleWidth: CGFloat {
        get {
            guard let value = defaults.object(forKey: widthKey) as? Double else {
                return Constants.marqueeVisibleWidth
            }
            return CGFloat(value).clamped(minVisibleWidth, maxVisibleWidth)
        }
        set { defaults.set(Double(newValue.clamped(minVisibleWidth, maxVisibleWidth)), forKey: widthKey) }
    }
}

private extension CGFloat {
    func clamped(_ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        Swift.min(Swift.max(self, lower), upper)
    }
}
