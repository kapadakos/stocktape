//
//  Logger.swift
//  StockTape
//
//  Lightweight file logger writing to ~/.stocktape/stocktape.log.
//  Rotates on launch when the file exceeds Constants.logMaxBytes.
//
//  Never log credential values (tokens, client secret). Callers are
//  responsible for redacting; this type makes no attempt to scrub input.
//

import Foundation

final class Logger {

    enum Level: String {
        case info = "INFO"
        case warn = "WARN"
        case error = "ERROR"
    }

    static let shared = Logger()

    /// ~/.stocktape/
    let directoryURL: URL
    /// ~/.stocktape/stocktape.log
    let fileURL: URL

    private let queue = DispatchQueue(label: "com.stocktape.logger")
    private let isoFormatter: ISO8601DateFormatter

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        directoryURL = home.appendingPathComponent(".stocktape", isDirectory: true)
        fileURL = directoryURL.appendingPathComponent("stocktape.log", isDirectory: false)

        isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        ensureDirectoryExists()
        rotateIfNeeded()
    }

    // MARK: - Public API

    func info(_ message: String) { write(.info, message) }
    func warn(_ message: String) { write(.warn, message) }
    func error(_ message: String) { write(.error, message) }

    // MARK: - Writing

    private func write(_ level: Level, _ message: String) {
        let timestamp = isoFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(level.rawValue)] \(message)\n"

        // Echo to stderr in debug builds for convenience during development.
        #if DEBUG
        FileHandle.standardError.write(Data(line.utf8))
        #endif

        queue.async { [fileURL] in
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    // MARK: - Setup & rotation

    private func ensureDirectoryExists() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directoryURL.path) {
            try? fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: fileURL.path) {
            fm.createFile(atPath: fileURL.path, contents: nil)
        }
    }

    /// On launch, if the log exceeds the size cap, keep only the last N lines.
    private func rotateIfNeeded() {
        let fm = FileManager.default
        guard
            let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
            let size = attrs[.size] as? Int,
            size > Constants.logMaxBytes
        else { return }

        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
        let kept = lines.suffix(Constants.logRotationKeepLines)
        let trimmed = kept.joined(separator: "\n")
        try? trimmed.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
