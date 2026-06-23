//
//  YahooFinanceClient.swift
//  StockTape
//
//  Fetches real-time and extended-hours quotes from Yahoo Finance's public
//  chart endpoint. No API key required. Used as the primary quote source so
//  the ticker shows accurate prices and percent-changes even after hours.
//
//  Priority order for current price:
//    1. Post-market  (4 PM – 8 PM ET)
//    2. Pre-market   (4 AM – 9:30 AM ET)
//    3. Regular market (last close)
//
//  Percent change is always relative to the previous regular-session close.
//

import Foundation

final class YahooFinanceClient {

    struct Quote {
        let symbol: String
        let price: Double
        let percentChange: Double
    }

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    /// Fetch quotes for all symbols in parallel. Returns a dict of whatever
    /// succeeded; missing entries mean Yahoo had no data for that symbol.
    func fetchQuotes(symbols: [String],
                     completion: @escaping ([String: Quote]) -> Void) {
        guard !symbols.isEmpty else { completion([:]); return }

        let group = DispatchGroup()
        var results: [String: Quote] = [:]
        let lock = NSLock()

        for symbol in symbols {
            group.enter()
            fetchSingle(symbol: symbol) { quote in
                if let quote {
                    lock.lock()
                    results[symbol] = quote
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .global()) { completion(results) }
    }

    // MARK: - Private

    private func fetchSingle(symbol: String, completion: @escaping (Quote?) -> Void) {
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        guard let url = URL(string:
            "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)" +
            "?interval=1d&range=1d&includePrePost=true") else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        // A browser-style User-Agent ensures Yahoo returns JSON rather than HTML.
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent")

        Logger.shared.info("Yahoo GET \(url.absoluteString)")

        session.dataTask(with: request) { data, response, error in
            if let error {
                Logger.shared.warn("Yahoo fetch failed for \(symbol): \(error.localizedDescription)")
                completion(nil)
                return
            }
            guard let data,
                  let decoded = try? JSONDecoder().decode(YFChartResponse.self, from: data),
                  let meta = decoded.chart.result?.first?.meta else {
                Logger.shared.warn("Yahoo: could not parse response for \(symbol)")
                completion(nil)
                return
            }

            let prevClose = meta.chartPreviousClose ?? meta.regularMarketPreviousClose ?? 0
            guard prevClose > 0 else { completion(nil); return }

            let (price, pct): (Double, Double)

            if let post = meta.postMarketPrice, post > 0 {
                price = post
                pct   = (post - prevClose) / prevClose * 100
            } else if let pre = meta.preMarketPrice, pre > 0 {
                price = pre
                pct   = (pre - prevClose) / prevClose * 100
            } else if let reg = meta.regularMarketPrice, reg > 0 {
                price = reg
                pct   = meta.regularMarketChangePercent
                    ?? ((reg - prevClose) / prevClose * 100)
            } else {
                completion(nil)
                return
            }

            completion(Quote(symbol: symbol, price: price, percentChange: pct))
        }.resume()
    }
}

// MARK: - Decodable response models (private to this file)

private struct YFChartResponse: Decodable {
    let chart: YFChart
}

private struct YFChart: Decodable {
    let result: [YFResult]?
}

private struct YFResult: Decodable {
    let meta: YFMeta
}

private struct YFMeta: Decodable {
    let regularMarketPrice: Double?
    let regularMarketPreviousClose: Double?
    let chartPreviousClose: Double?
    let preMarketPrice: Double?
    let postMarketPrice: Double?
    let regularMarketChangePercent: Double?
}
