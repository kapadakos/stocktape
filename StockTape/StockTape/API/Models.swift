//
//  Models.swift
//  StockTape
//
//  Decodable models for the Schwab Trader and Market Data APIs, plus a small
//  view model (`PositionDisplay`) that the UI layer consumes.
//

import Foundation

// MARK: - Accounts

struct AccountNumber: Decodable {
    let accountNumber: String
    let hashValue: String
}

struct AccountResponse: Decodable {
    let securitiesAccount: SecuritiesAccount
}

struct SecuritiesAccount: Decodable {
    let positions: [Position]?
}

struct Position: Decodable {
    let instrument: Instrument
    let longQuantity: Double
    let shortQuantity: Double
    let marketValue: Double
    /// Average cost per share. Optional because some asset types omit it.
    let averagePrice: Double?

    /// Signed share count: positive for long, negative for short.
    var netQuantity: Double { longQuantity - shortQuantity }
}

struct Instrument: Decodable {
    let symbol: String
    let assetType: String
}

// MARK: - Quotes

/// The quotes endpoint returns a JSON object keyed by symbol, e.g.
/// `{ "AAPL": { "quote": { ... } }, "NVDA": { "quote": { ... } } }`.
/// Symbols that fail to resolve may be missing their `quote` object, so it is
/// modelled as optional.
struct QuoteContainer: Decodable {
    let quote: Quote?
}

struct Quote: Decodable {
    let mark: Double?
    let lastPrice: Double?
    let netPercentChange: Double?
    let closePrice: Double?

    /// Current price: `mark`, falling back to `lastPrice` (used for crypto).
    var currentPrice: Double? {
        mark ?? lastPrice
    }

    /// Signed percent change for the day; treated as flat when absent.
    var percentChange: Double {
        netPercentChange ?? 0
    }
}

// MARK: - View model

/// A single resolved position ready for display in the marquee and dropdown.
struct PositionDisplay {
    let symbol: String
    let price: Double
    let percentChange: Double
    /// Total unrealized gain/loss in dollars: (price − avg cost) × quantity.
    /// `nil` when the cost basis is unknown.
    let totalPnL: Double?
    /// Total return as a percent of cost basis. `nil` when cost basis is unknown.
    let totalReturnPercent: Double?

    enum Direction {
        case up, down, flat
    }

    var direction: Direction {
        if percentChange > 0 { return .up }
        if percentChange < 0 { return .down }
        return .flat
    }
}
