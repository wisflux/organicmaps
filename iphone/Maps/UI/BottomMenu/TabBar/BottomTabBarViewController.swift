
private let kUDDidShowFirstTimeRoutingEducationalHint = "kUDDidShowFirstTimeRoutingEducationalHint"

class BottomTabBarViewController: UIViewController {
  var presenter: BottomTabBarPresenterProtocol!
  
  @IBOutlet var searchButton: MWMButton!
  @IBOutlet var helpButton: MWMButton!
  @IBOutlet var bookmarksButton: MWMButton!
  @IBOutlet var AlertsButton: MWMButton!
  @IBOutlet var moreButton: MWMButton!
  @IBOutlet var downloadBadge: UIView!
  @IBOutlet var helpBadge: UIView!
  
  private var avaliableArea = CGRect.zero
  @objc var isHidden: Bool = false {
    didSet {
      updateFrame(animated: true)
    }
  }
  @objc var isApplicationBadgeHidden: Bool = true {
    didSet {
      updateBadge()
    }
  }
  var tabBarView: BottomTabBarView {
    return view as! BottomTabBarView
  }
  @objc static var controller: BottomTabBarViewController? {
    return MWMMapViewControlsManager.manager()?.tabBarController
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    presenter.configure()
    var size = CGSize(width: 48, height: 48);
    AlertsButton.size = size;
    AlertsButton.applyTheme();
    MWMSearchManager.add(self)
  }
  
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    if Settings.isNY() {
      helpButton.setTitle("🎄", for: .normal)
      helpButton.setImage(nil, for: .normal)
    }
    updateBadge()
  }
  
  deinit {
    MWMSearchManager.remove(self)
  }
  
  static func updateAvailableArea(_ frame: CGRect) {
    BottomTabBarViewController.controller?.updateAvailableArea(frame)
  }
  
  @IBAction func onSearchButtonPressed(_ sender: Any) {
    presenter.onSearchButtonPressed()
  }

  @IBAction func onAlertsButtonPressed(_ sender: Any) {
    presenter.onAlertsButtonPressed()
  }
  
  @IBAction func onHelpButtonPressed(_ sender: Any) {
    if !helpBadge.isHidden {
      presenter.onHelpButtonPressed(withBadge: true)
      setHelpBadgeShown()
    } else {
      presenter.onHelpButtonPressed(withBadge: false)
    }
  }
  
  @IBAction func onBookmarksButtonPressed(_ sender: Any) {
    presenter.onBookmarksButtonPressed()
  }
  
  @IBAction func onMenuButtonPressed(_ sender: Any) {
    presenter.onMenuButtonPressed()
  }
  
  private func updateAvailableArea(_ frame:CGRect) {
    avaliableArea = frame
    updateFrame(animated: false)
    self.view.layoutIfNeeded()
  }
  
  private func updateFrame(animated: Bool) {
    if avaliableArea == .zero {
      return
    }
    let newFrame = CGRect(x: avaliableArea.minX,
                          y: isHidden ? avaliableArea.minY + avaliableArea.height : avaliableArea.minY,
                          width: avaliableArea.width,
                          height: avaliableArea.height)
    let alpha:CGFloat = isHidden ? 0 : 1
    if animated {
      UIView.animate(withDuration: kDefaultAnimationDuration,
                     delay: 0,
                     options: [.beginFromCurrentState],
                     animations: {
        self.view.frame = newFrame
        self.view.alpha = alpha
      }, completion: nil)
    } else {
      self.view.frame = newFrame
      self.view.alpha = alpha
    }
  }
  
  private func updateBadge() {
    downloadBadge.isHidden = isApplicationBadgeHidden
    helpBadge.isHidden = !needsToShowHelpBadge()
  }
}

// MARK: - Help badge
private extension BottomTabBarViewController {
  private func needsToShowHelpBadge() -> Bool {
    !UserDefaults.standard.bool(forKey: kUDDidShowFirstTimeRoutingEducationalHint)
  }
  
  private func setHelpBadgeShown() {
    UserDefaults.standard.set(true, forKey: kUDDidShowFirstTimeRoutingEducationalHint)
  }
}

// MARK: - MWMSearchManagerObserver
extension BottomTabBarViewController: MWMSearchManagerObserver {
  func onSearchManagerStateChanged() {
    let state = MWMSearchManager.manager().state;
    self.searchButton.isSelected = state != .hidden
  }
}
