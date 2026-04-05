//
//  BioTrackerWebView.swift
//  healthsync
//
//  Created by Alaric Moore on 4/5/26.
//

import SwiftUI
import WebKit

struct BioTrackerWebView: View {
    let baseURL: String
    let path: String

    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            if let errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Can't reach biotracker")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        self.errorMessage = nil
                        isLoading = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else {
                WebViewRepresentable(
                    url: URL(string: baseURL + path)!,
                    baseHost: URL(string: baseURL)?.host ?? "",
                    isLoading: $isLoading,
                    errorMessage: $errorMessage
                )
                .ignoresSafeArea(edges: .bottom)

                if isLoading {
                    ProgressView("Loading...")
                }
            }
        }
    }
}

// MARK: - WKWebView UIViewRepresentable

struct WebViewRepresentable: UIViewRepresentable {
    let url: URL
    let baseHost: String
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Reload if error was cleared (retry tapped)
        if errorMessage == nil && isLoading && webView.url == nil {
            webView.load(URLRequest(url: url))
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: WebViewRepresentable

        init(_ parent: WebViewRepresentable) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async { self.parent.isLoading = true }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.errorMessage = nil
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.errorMessage = "Is Tailscale connected?\n\(error.localizedDescription)"
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.errorMessage = error.localizedDescription
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            // Allow navigation within the biotracker domain
            if let host = url.host, host == parent.baseHost {
                decisionHandler(.allow)
                return
            }

            // Allow initial load and same-origin requests
            if navigationAction.targetFrame?.isMainFrame == true && url.host == nil {
                decisionHandler(.allow)
                return
            }

            // External links → open in Safari
            if url.scheme == "http" || url.scheme == "https" {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }
    }
}
