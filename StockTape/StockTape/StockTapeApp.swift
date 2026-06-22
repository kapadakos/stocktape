//
//  StockTapeApp.swift
//  StockTape
//
//  Entry point. StockTape is a menu-bar-only agent app (LSUIElement), so there
//  is no real window scene — all UI lives in the status item and the onboarding
//  window created by AppDelegate. The empty Settings scene satisfies the App
//  protocol without putting anything on screen.
//

import SwiftUI

@main
struct StockTapeApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
