//
//  CallbackServer.swift
//  StockTape
//
//  Minimal loopback HTTP listener built on Network.framework. It captures the
//  single OAuth redirect request, reconstructs the full redirect URL, and hands
//  it back exactly once. The listener is cancelled the instant a request is
//  captured — we never leave a socket open.
//
//  Note on Schwab: Schwab redirects to `https://127.0.0.1` (port 443, HTTPS).
//  A plain TCP listener on Constants.callbackServerPort will only ever receive
//  the redirect if the user (or a proxy) points the browser at that port, so in
//  practice AuthManager also offers a manual paste-the-URL path. This server is
//  the automatic fast path described in the spec and the fallback to
//  ASWebAuthenticationSession.
//

import Foundation
import Network

final class CallbackServer {

    enum CallbackError: Error {
        case malformedRequest
        case invalidURL
        case listenerFailed(Error)
    }

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.stocktape.callbackserver")
    private var completion: ((Result<URL, Error>) -> Void)?
    private var finished = false

    /// Begin listening. `completion` is delivered on the main queue exactly once.
    func start(port: UInt16 = Constants.callbackServerPort,
               completion: @escaping (Result<URL, Error>) -> Void) {
        self.completion = completion

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            deliver(.failure(CallbackError.invalidURL))
            return
        }

        do {
            let listener = try NWListener(using: .tcp, on: nwPort)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed(let error) = state {
                    self?.deliver(.failure(CallbackError.listenerFailed(error)))
                }
            }
            listener.start(queue: queue)
            Logger.shared.info("CallbackServer listening on port \(port)")
        } catch {
            Logger.shared.error("CallbackServer failed to start: \(error.localizedDescription)")
            deliver(.failure(CallbackError.listenerFailed(error)))
        }
    }

    /// Stop listening. Safe to call multiple times.
    func cancel() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, !data.isEmpty, let request = String(data: data, encoding: .utf8) {
                self.process(request, on: connection)
            } else if let error {
                self.respondAndClose(connection)
                self.deliver(.failure(CallbackError.listenerFailed(error)))
            } else {
                self.respondAndClose(connection)
                self.deliver(.failure(CallbackError.malformedRequest))
            }
        }
    }

    private func process(_ request: String, on connection: NWConnection) {
        // First request line looks like: "GET /?code=...&state=... HTTP/1.1"
        guard
            let firstLine = request.split(separator: "\r\n", maxSplits: 1).first,
            case let parts = firstLine.split(separator: " "),
            parts.count >= 2
        else {
            respondAndClose(connection)
            deliver(.failure(CallbackError.malformedRequest))
            return
        }

        let path = String(parts[1])
        let urlString = Constants.redirectURI + (path.hasPrefix("/") ? path : "/" + path)

        respondAndClose(connection)

        if let url = URL(string: urlString) {
            deliver(.success(url))
        } else {
            deliver(.failure(CallbackError.invalidURL))
        }
    }

    private func respondAndClose(_ connection: NWConnection) {
        let body = """
        <!doctype html><html><head><meta charset="utf-8">
        <title>StockTape</title></head>
        <body style="font-family:-apple-system,Helvetica,Arial,sans-serif;background:#1c1c1e;color:#fff;display:flex;height:100vh;align-items:center;justify-content:center;margin:0">
        <div style="text-align:center"><h2>StockTape connected ✅</h2>
        <p>You can close this window and return to StockTape.</p></div>
        </body></html>
        """
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - One-shot delivery

    private func deliver(_ result: Result<URL, Error>) {
        guard !finished else { return }
        finished = true
        let completion = self.completion
        self.completion = nil
        cancel()
        DispatchQueue.main.async { completion?(result) }
    }
}
