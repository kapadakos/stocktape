//
//  AuthManager.swift
//  StockTape
//
//  Orchestrates the Schwab OAuth2 authorization-code flow and the full token
//  lifecycle. Credentials and tokens live exclusively in the Keychain; this
//  type never writes them to disk or logs them.
//
//  Flow summary:
//    1. beginAuthorization() builds the authorize URL and opens the browser.
//    2. The redirect is captured automatically by CallbackServer, or manually
//       via a paste prompt (Schwab redirects to https://127.0.0.1 with no port,
//       which a browser cannot load locally — the user copies the URL from the
//       address bar).
//    3. The captured code is exchanged for tokens, which are stored in Keychain.
//    4. validAccessToken(completion:) refreshes silently before each API call.
//

import Foundation
import AppKit

final class AuthManager {

    static let shared = AuthManager()

    // Posted on the main thread so AppDelegate can react.
    static let didAuthenticate = Notification.Name("StockTape.didAuthenticate")
    static let didFailAuthentication = Notification.Name("StockTape.didFailAuthentication")
    static let didRequireReauth = Notification.Name("StockTape.didRequireReauth")

    enum AuthError: LocalizedError {
        case missingCredentials
        case stateMismatch
        case providerError(String)
        case missingCode
        case tokenExchangeFailed(Int)
        case refreshFailed(Int)
        case noRefreshToken
        case decodingFailed
        case network(Error)

        var errorDescription: String? {
            switch self {
            case .missingCredentials: return "Client ID and Secret are required."
            case .stateMismatch: return "OAuth state mismatch — the response may not be genuine."
            case .providerError(let message): return "Schwab returned an error: \(message)"
            case .missingCode: return "No authorization code was found in the redirect."
            case .tokenExchangeFailed(let code): return "Token exchange failed (HTTP \(code))."
            case .refreshFailed(let code): return "Token refresh failed (HTTP \(code))."
            case .noRefreshToken: return "No refresh token is stored. Please re-authenticate."
            case .decodingFailed: return "Could not parse the token response."
            case .network(let error): return error.localizedDescription
            }
        }
    }

    private let session = URLSession(configuration: .ephemeral)
    private let isoFormatter: ISO8601DateFormatter

    private var pendingState: String?
    private var callbackServer: CallbackServer?
    private var isConsuming = false

    private init() {
        isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
    }

    // MARK: - Credential / token state

    var hasCredentials: Bool {
        Keychain.has(.clientID) && Keychain.has(.clientSecret)
    }

    var hasRefreshToken: Bool {
        Keychain.has(.refreshToken)
    }

    var isAuthenticated: Bool {
        hasCredentials && hasRefreshToken
    }

    @discardableResult
    func saveCredentials(clientID: String, clientSecret: String) -> Bool {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !secret.isEmpty else { return false }
        let ok = Keychain.set(id, for: .clientID) && Keychain.set(secret, for: .clientSecret)
        Logger.shared.info("Saved Schwab credentials to Keychain (success=\(ok)).")
        return ok
    }

    func clearTokens() {
        Keychain.delete(.accessToken)
        Keychain.delete(.refreshToken)
        Keychain.delete(.tokenExpiry)
        Logger.shared.info("Cleared stored tokens.")
    }

    func clearAllCredentials() {
        Keychain.deleteAll()
        Logger.shared.info("Cleared all Keychain credentials.")
    }

    // MARK: - Authorization

    func beginAuthorization() {
        guard let clientID = Keychain.get(.clientID), !clientID.isEmpty else {
            postFailure(AuthError.missingCredentials)
            return
        }

        let state = UUID().uuidString
        pendingState = state
        isConsuming = false

        var components = URLComponents(string: Constants.authorizationURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: Constants.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Constants.oauthScope),
            URLQueryItem(name: "state", value: state),
        ]

        guard let authURL = components.url else {
            postFailure(AuthError.missingCredentials)
            return
        }

        Logger.shared.info("Opening Schwab authorization URL in browser.")
        NSWorkspace.shared.open(authURL)

        // Automatic capture path.
        let server = CallbackServer()
        callbackServer = server
        server.start { [weak self] result in
            switch result {
            case .success(let url):
                self?.consume(redirectURL: url)
            case .failure(let error):
                // Don't surface listener failures as user errors — the manual
                // paste path is still available. Just log.
                Logger.shared.warn("CallbackServer did not capture redirect: \(error.localizedDescription)")
            }
        }

        // Manual capture path (reliable for Schwab's no-port HTTPS redirect).
        DispatchQueue.main.async { [weak self] in
            self?.promptForRedirectURL()
        }
    }

    /// Present an alert asking the user to paste the redirect URL from their
    /// browser's address bar after approving access.
    private func promptForRedirectURL() {
        // An LSUIElement app isn't active by default; make sure the modal is
        // frontmost and can take keyboard focus.
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Finish connecting to Schwab"
        alert.informativeText = """
        A browser window has opened for Schwab login. After you approve access, \
        your browser will try to load a page at https://127.0.0.1 and show a \
        "can't connect" error — that is expected.

        Copy the full URL from the browser's address bar and paste it below.
        """
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "https://127.0.0.1/?code=...&state=..."
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.window.level = .floating

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            Logger.shared.info("User cancelled manual redirect entry.")
            return
        }

        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text) else {
            postFailure(AuthError.missingCode)
            return
        }
        consume(redirectURL: url)
    }

    /// Validate and process a captured redirect URL. Only the first caller wins.
    private func consume(redirectURL url: URL) {
        guard !isConsuming else { return }
        isConsuming = true

        callbackServer?.cancel()
        callbackServer = nil

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            postFailure(AuthError.missingCode)
            return
        }
        let items = components.queryItems ?? []

        if let providerError = items.first(where: { $0.name == "error" })?.value {
            postFailure(AuthError.providerError(providerError))
            return
        }

        let returnedState = items.first(where: { $0.name == "state" })?.value
        guard returnedState == pendingState else {
            Logger.shared.error("OAuth state mismatch — aborting.")
            postFailure(AuthError.stateMismatch)
            return
        }

        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            postFailure(AuthError.missingCode)
            return
        }

        Logger.shared.info("Captured authorization code; exchanging for tokens.")
        exchangeCodeForTokens(code)
    }

    // MARK: - Token exchange & refresh

    private func exchangeCodeForTokens(_ code: String) {
        let params = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Constants.redirectURI,
        ]
        requestTokens(parameters: params, failureWrap: AuthError.tokenExchangeFailed) { [weak self] result in
            switch result {
            case .success:
                Logger.shared.info("Token exchange succeeded.")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: AuthManager.didAuthenticate, object: nil)
                }
            case .failure(let error):
                self?.postFailure(error)
            }
        }
    }

    /// Return a valid access token, refreshing first if it is near expiry.
    /// Completion is delivered on the main thread.
    func validAccessToken(completion: @escaping (Result<String, Error>) -> Void) {
        let now = Date()
        let needsRefresh: Bool = {
            guard let token = Keychain.get(.accessToken), !token.isEmpty else { return true }
            guard let expiryString = Keychain.get(.tokenExpiry),
                  let expiry = isoFormatter.date(from: expiryString) else { return true }
            return expiry < now.addingTimeInterval(Constants.tokenExpiryBuffer)
        }()

        if !needsRefresh, let token = Keychain.get(.accessToken) {
            DispatchQueue.main.async { completion(.success(token)) }
            return
        }

        refreshTokens { result in
            switch result {
            case .success:
                if let token = Keychain.get(.accessToken) {
                    DispatchQueue.main.async { completion(.success(token)) }
                } else {
                    DispatchQueue.main.async { completion(.failure(AuthError.noRefreshToken)) }
                }
            case .failure(let error):
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    /// Force a token refresh. Used by validAccessToken and after a 401.
    func refreshTokens(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let refreshToken = Keychain.get(.refreshToken), !refreshToken.isEmpty else {
            completion(.failure(AuthError.noRefreshToken))
            return
        }

        Logger.shared.info("Refreshing access token.")
        let params = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ]
        requestTokens(parameters: params, failureWrap: AuthError.refreshFailed) { result in
            switch result {
            case .success:
                Logger.shared.info("Token refresh succeeded.")
                completion(.success(()))
            case .failure(let error):
                // A 401 on refresh means the refresh token is dead (>7 days):
                // clear everything and trigger a full re-auth.
                if case AuthError.refreshFailed(401) = error {
                    Logger.shared.warn("Refresh token rejected (401); clearing tokens and requiring re-auth.")
                    self.clearTokens()
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: AuthManager.didRequireReauth, object: nil)
                    }
                }
                completion(.failure(error))
            }
        }
    }

    // MARK: - Shared token request

    private func requestTokens(parameters: [String: String],
                               failureWrap: @escaping (Int) -> AuthError,
                               completion: @escaping (Result<Void, Error>) -> Void) {
        // Run keychain reads and network setup on a background thread so the
        // main thread stays free (blocking it here would prevent any keychain
        // auth dialog from drawing, causing a beach ball).
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.performRequestTokens(parameters: parameters,
                                      failureWrap: failureWrap,
                                      completion: completion)
        }
    }

    private func performRequestTokens(parameters: [String: String],
                                      failureWrap: @escaping (Int) -> AuthError,
                                      completion: @escaping (Result<Void, Error>) -> Void) {
        guard let clientID = Keychain.get(.clientID),
              let clientSecret = Keychain.get(.clientSecret) else {
            completion(.failure(AuthError.missingCredentials))
            return
        }

        guard let url = URL(string: Constants.tokenURL) else {
            completion(.failure(AuthError.missingCredentials))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let credentials = "\(clientID):\(clientSecret)"
        let basic = Data(credentials.utf8).base64EncodedString()
        request.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")

        request.httpBody = formURLEncoded(parameters).data(using: .utf8)

        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            if let error {
                completion(.failure(AuthError.network(error)))
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(status), let data else {
                Logger.shared.error("Token endpoint returned HTTP \(status).")
                completion(.failure(failureWrap(status)))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
                self.store(decoded)
                completion(.success(()))
            } catch {
                completion(.failure(AuthError.decodingFailed))
            }
        }.resume()
    }

    private func store(_ tokens: TokenResponse) {
        Keychain.set(tokens.accessToken, for: .accessToken)
        Keychain.set(tokens.refreshToken, for: .refreshToken)

        let accessExpiry = Date().addingTimeInterval(TimeInterval(tokens.expiresIn))
        Keychain.set(isoFormatter.string(from: accessExpiry), for: .tokenExpiry)

        // Schwab returns `refresh_token_expires_in` when available; default to 7 days.
        let refreshLifetime = TimeInterval(tokens.refreshTokenExpiresIn ?? 7 * 24 * 3600)
        let refreshExpiry = Date().addingTimeInterval(refreshLifetime)
        Keychain.set(isoFormatter.string(from: refreshExpiry), for: .refreshTokenExpiry)
    }

    /// True when the refresh token will expire within the next 24 hours.
    var isRefreshTokenExpiringSoon: Bool {
        guard let expiryString = Keychain.get(.refreshTokenExpiry),
              let expiry = isoFormatter.date(from: expiryString) else { return false }
        return expiry < Date().addingTimeInterval(24 * 3600)
    }

    /// Approximate time until the refresh token expires, or nil if unknown.
    var refreshTokenExpiresAt: Date? {
        guard let expiryString = Keychain.get(.refreshTokenExpiry) else { return nil }
        return isoFormatter.date(from: expiryString)
    }

    // MARK: - Helpers

    private func formURLEncoded(_ params: [String: String]) -> String {
        params.map { key, value in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
    }

    private func postFailure(_ error: Error) {
        Logger.shared.error("Authentication failed: \(error.localizedDescription)")
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: AuthManager.didFailAuthentication,
                                            object: nil,
                                            userInfo: ["error": error])
        }
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
        let refreshTokenExpiresIn: Int?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case refreshTokenExpiresIn = "refresh_token_expires_in"
        }
    }
}

private extension CharacterSet {
    /// Characters allowed in an x-www-form-urlencoded value.
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}
