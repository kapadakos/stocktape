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

    /// Timer fires at 60 fps for pixel-smooth scrolling.
    static let marqueeTickInterval: TimeInterval = 1.0 / 60.0

    /// Points advanced per tick. 1.5 pt × 60 fps = 90 pt/sec ≈ 13 chars/sec.
    static let marqueeScrollSpeed: CGFloat = 1.5

    /// Visible pixel width of the scrolling window (matches the fixed status item width).
    static let marqueeDisplayWidth: CGFloat = 196

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
