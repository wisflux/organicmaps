final class AlertsViewController: MWMViewController {
  override func loadView() {
    super.loadView()

    // TODO: FAQ?
    self.title = L("Alerts")

    let webViewController = WebViewController.init(url:URL(string:"https://drimsplatform.com/alerts")!, title: "Alerts")!
    webViewController.openInSafari = true
    addChild(webViewController)
    let aboutView = webViewController.view!
    view.addSubview(aboutView)
    aboutView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      aboutView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      aboutView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      aboutView.topAnchor.constraint(equalTo: view.topAnchor),
      aboutView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])
  }
}
