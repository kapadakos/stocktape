//
//  SchwabClient.swift
//  StockTape
//
//  All Schwab Trader + Market Data calls. Each refresh runs the three-step
//  sequence: account numbers → positions (per account, merged) → batched quotes.
//
//  Every request carries `Authorization: Bearer <token>` and `Accept:
//  application/json`. Tokens are sourced from AuthManager, which refreshes
//  silently. A 401 triggers one refresh-and-retry; a 429 triggers one backoff
//  -and-retry. Results are delivered on the main thread.
//

import Foundation

final class SchwabClient {

    enum ClientError: LocalizedError {
        case http(Int)
        case noData
        case decoding
        case noAccounts
        case auth(Error)
        case network(Error)

        var errorDescription: String? {
            switch self {
            case .http(let code): return "Schwab API returned HTTP \(code)."
            case .noData: return "Schwab API returned no data."
            case .decoding: return "Could not parse the Schwab API response."
            case .noAccounts: return "No Schwab accounts were found."
            case .auth(let error): return error.localizedDescription
            case .network(let error): return error.localizedDescription
            }
        }
    }

    private let auth: AuthManager
    private let session: URLSession

    init(auth: AuthManager = .shared) {
        self.auth = auth
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public entry point

    /// Run the full refresh sequence and return display-ready positions.
    /// Completion is always delivered on the main thread.
    func fetchPositions(completion: @escaping (Result<[PositionDisplay], Error>) -> Void) {
        let mainCompletion: (Result<[PositionDisplay], Error>) -> Void = { result in
            if Thread.isMainThread {
                completion(result)
            } else {
                DispatchQueue.main.async { completion(result) }
            }
        }
        runFetchSequence(completion: mainCompletion)
    }

    private func runFetchSequence(completion: @escaping (Result<[PositionDisplay], Error>) -> Void) {
        fetchAccountHashes { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let hashes):
                guard !hashes.isEmpty else {
                    completion(.failure(ClientError.noAccounts))
                    return
                }
                self.fetchPositions(forHashes: hashes) { positionsResult in
                    switch positionsResult {
                    case .failure(let error):
                        completion(.failure(error))
                    case .success(let positions):
                        self.resolve(positions: positions, completion: completion)
                    }
                }
            }
        }
    }

    // MARK: - Step 1: account numbers

    private func fetchAccountHashes(completion: @escaping (Result<[String], Error>) -> Void) {
        get(Constants.accountNumbersURL, as: [AccountNumber].self) { result in
            completion(result.map { $0.map(\.hashValue) })
        }
    }

    // MARK: - Step 2: positions (one call per account, merged)

    private func fetchPositions(forHashes hashes: [String],
                                completion: @escaping (Result<[Position], Error>) -> Void) {
        let group = DispatchGroup()
        var merged: [Position] = []
        var firstError: Error?
        let lock = NSLock()

        for hash in hashes {
            group.enter()
            let urlString = "\(Constants.accountsBaseURL)/\(hash)?fields=positions"
            get(urlString, as: AccountResponse.self) { result in
                lock.lock()
                switch result {
                case .success(let response):
                    merged.append(contentsOf: response.securitiesAccount.positions ?? [])
                case .failure(let error):
                    if firstError == nil { firstError = error }
                }
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) {
            if let error = firstError, merged.isEmpty {
                completion(.failure(error))
            } else {
                completion(.success(merged))
            }
        }
    }

    // MARK: - Step 3: quotes

    private func resolve(positions: [Position],
                         completion: @escaping (Result<[PositionDisplay], Error>) -> Void) {
        // Keep only open, non-cash positions.
        let openPositions = positions.filter { position in
            position.instrument.assetType != "CASH_EQUIVALENT"
                && (position.longQuantity > 0 || position.shortQuantity > 0)
        }

        let symbols = orderedUniqueSymbols(from: openPositions)
        guard !symbols.isEmpty else {
            completion(.success([]))
            return
        }

        fetchQuotes(for: symbols) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let quotes):
                let displays: [PositionDisplay] = symbols.compactMap { symbol in
                    guard let quote = quotes[symbol]?.quote,
                          let price = quote.currentPrice else { return nil }
                    return PositionDisplay(symbol: symbol,
                                           price: price,
                                           percentChange: quote.percentChange)
                }
                completion(.success(displays))
            }
        }
    }

    private func fetchQuotes(for symbols: [String],
                             completion: @escaping (Result<[String: QuoteContainer], Error>) -> Void) {
        var components = URLComponents(string: Constants.quotesURL)!
        components.queryItems = [
            URLQueryItem(name: "symbols", value: symbols.joined(separator: ",")),
            URLQueryItem(name: "fields", value: "quote"),
        ]
        guard let url = components.url else {
            completion(.failure(ClientError.noData))
            return
        }
        get(url.absoluteString, as: QuotesResponse.self) { result in
            completion(result.map(\.quotes))
        }
    }

    private func orderedUniqueSymbols(from positions: [Position]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for position in positions {
            let symbol = position.instrument.symbol
            if seen.insert(symbol).inserted {
                ordered.append(symbol)
            }
        }
        return ordered
    }

    // MARK: - Authorized GET with 401/429 handling

    private func get<T: Decodable>(_ urlString: String,
                                   as type: T.Type,
                                   allowRetryOn401: Bool = true,
                                   allowRetryOn429: Bool = true,
                                   completion: @escaping (Result<T, Error>) -> Void) {
        auth.validAccessToken { [weak self] tokenResult in
            guard let self else { return }
            switch tokenResult {
            case .failure(let error):
                completion(.failure(ClientError.auth(error)))
            case .success(let token):
                self.performGet(urlString,
                                token: token,
                                as: type,
                                allowRetryOn401: allowRetryOn401,
                                allowRetryOn429: allowRetryOn429,
                                completion: completion)
            }
        }
    }

    private func performGet<T: Decodable>(_ urlString: String,
                                          token: String,
                                          as type: T.Type,
                                          allowRetryOn401: Bool,
                                          allowRetryOn429: Bool,
                                          completion: @escaping (Result<T, Error>) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(.failure(ClientError.noData))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Log the URL but never the auth header.
        Logger.shared.info("GET \(url.absoluteString)")

        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }

            if let error {
                Logger.shared.error("Network error for \(url.path): \(error.localizedDescription)")
                completion(.failure(ClientError.network(error)))
                return
            }

            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            switch status {
            case 200...299:
                guard let data else {
                    completion(.failure(ClientError.noData))
                    return
                }
                do {
                    let decoded = try JSONDecoder().decode(T.self, from: data)
                    completion(.success(decoded))
                } catch {
                    Logger.shared.error("Decoding failed for \(url.path): \(error)")
                    completion(.failure(ClientError.decoding))
                }

            case 401 where allowRetryOn401:
                Logger.shared.warn("HTTP 401 on \(url.path); refreshing token and retrying once.")
                self.auth.refreshTokens { refreshResult in
                    switch refreshResult {
                    case .success:
                        self.get(urlString, as: type, allowRetryOn401: false,
                                 allowRetryOn429: allowRetryOn429, completion: completion)
                    case .failure(let error):
                        completion(.failure(ClientError.auth(error)))
                    }
                }

            case 429 where allowRetryOn429:
                Logger.shared.warn("HTTP 429 on \(url.path); backing off \(Int(Constants.rateLimitBackoff))s.")
                DispatchQueue.global().asyncAfter(deadline: .now() + Constants.rateLimitBackoff) {
                    self.get(urlString, as: type, allowRetryOn401: allowRetryOn401,
                             allowRetryOn429: false, completion: completion)
                }

            default:
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "<no body>"
                Logger.shared.error("HTTP \(status) on \(url.path). Body: \(body)")
                completion(.failure(ClientError.http(status)))
            }
        }.resume()
    }
}

// MARK: - Quotes response (resilient to the `errors` key)

/// The quotes endpoint returns a dictionary keyed by symbol, but may also
/// include an `errors` entry of a different shape. This decoder keeps only the
/// entries that decode cleanly as quotes.
struct QuotesResponse: Decodable {
    let quotes: [String: QuoteContainer]

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        var result: [String: QuoteContainer] = [:]
        for key in container.allKeys {
            if let quote = try? container.decode(QuoteContainer.self, forKey: key) {
                result[key.stringValue] = quote
            }
        }
        quotes = result
    }
}
