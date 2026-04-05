//
//  ContentView.swift
//  healthsync
//
//  Created by Alaric Moore on 3/29/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var syncer = HealthSyncer()

    @AppStorage("serverURL") private var serverURL = "https://<YOUR_SERVER>/api/health-sync"
    @AppStorage("apiToken") private var apiToken = ""
    @AppStorage("userID") private var userID = 1

    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            SyncSettingsView(syncer: syncer, serverURL: $serverURL, apiToken: $apiToken, userID: $userID)
                .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
                .tag(0)

            BioTrackerWebView(baseURL: baseURL, path: "/mobile/log")
                .tabItem { Label("Log", systemImage: "square.and.pencil") }
                .tag(1)

            BioTrackerWebView(baseURL: baseURL, path: "/mobile/status")
                .tabItem { Label("Risk", systemImage: "heart.text.square") }
                .tag(2)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openLogTab)) { _ in
            selectedTab = 1
        }
    }

    /// Derive base URL from the stored health-sync endpoint
    private var baseURL: String {
        serverURL.replacingOccurrences(of: "/api/health-sync", with: "")
    }
}

#Preview {
    ContentView()
}
