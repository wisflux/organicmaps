import UIKit
import WebKit

final class AlertsViewController: UIViewController {
    private var webView: WKWebView!

    override func loadView() {
        let webConfiguration = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: webConfiguration)
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Set the title of the screen
        self.title = "Alerts"

        // Define the URL for Google
        if let url = URL(string: "https://www.google.com") {
            // Create a URL request and load it in the web view
            let request = URLRequest(url: url)
            webView.load(request)
        }
    }
}