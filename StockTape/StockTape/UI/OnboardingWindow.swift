//
//  OnboardingWindow.swift
//  StockTape
//
//  First-run setup. A real, floating NSWindow (not a sheet) hosting a SwiftUI
//  form. Shown automatically when no credentials are in the Keychain. On
//  "Connect to Schwab" it saves the entered credentials and kicks off the
//  OAuth browser flow; AppDelegate closes the window on success.
//

import AppKit
import SwiftUI

final class OnboardingWindowController: NSWindowController {

    /// Called with (clientID, clientSecret) when the user taps "Connect".
    var onConnect: ((String, String) -> Void)?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "StockTape Setup"
        window.isReleasedWhenClosed = false
        window.level = .floating              // appear above other windows on first launch
        window.center()

        self.init(window: window)

        let view = OnboardingView { [weak self] clientID, secret in
            self?.onConnect?(clientID, secret)
        }
        window.contentViewController = NSHostingController(rootView: view)
    }

    /// Bring the app forward and show the window front and center.
    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - SwiftUI form

struct OnboardingView: View {

    let onConnect: (String, String) -> Void

    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var showValidationError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            HStack(spacing: 8) {
                Text("🖥")
                Text("StockTape Setup")
                    .font(.title2).bold()
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Text("StockTape connects to your Schwab account to display your live positions in the menu bar. You'll need to create a free Schwab Developer app first.")
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                if let url = URL(string: "https://developer.schwab.com") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Text("How to get your credentials ↗")
            }
            .buttonStyle(.link)

            VStack(alignment: .leading, spacing: 6) {
                Text("Client ID").font(.subheadline).bold()
                TextField("", text: $clientID)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Client Secret").font(.subheadline).bold()
                SecureField("", text: $clientSecret)
                    .textFieldStyle(.roundedBorder)
            }

            if showValidationError {
                Text("Both Client ID and Client Secret are required.")
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Button(action: connect) {
                Text("Connect to Schwab")
                    .frame(maxWidth: .infinity)
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)

            Text("Your credentials are stored only in your Mac's Keychain. StockTape never transmits them anywhere except to Schwab.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 420)
    }

    private func connect() {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !secret.isEmpty else {
            showValidationError = true
            return
        }
        showValidationError = false
        onConnect(id, secret)
    }
}
