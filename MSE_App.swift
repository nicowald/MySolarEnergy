//
//  MSEApp.swift
//  MSE Watch App
//
//  Created by Nico Wald on 2026-05-16.
//

import SwiftUI

@main
struct MSE_App: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // Fetch data when app becomes active
                    if let client = FEMSClient.shared {
                        client.fetchBattery()
                    }
                }
        }
    }
}
