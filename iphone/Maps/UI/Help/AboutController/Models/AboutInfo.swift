enum AboutInfo {
  case faq
  case noWifi

  var title: String {
    switch self {

    case .faq:
      return L("faq")
    case .noWifi:
      return L("about_proposition_2")
    }
  }

  var image: UIImage? {
    switch self {
    case .faq:
      return UIImage(named: "ic_about_faq")!
    case .noWifi:
      // Dots are used for these cases
      return nil
    }
  }

  var link: String? {
    switch self {
    case .faq, .noWifi:
      // These cases don't provide redirection to the web
      return nil
    }
  }
}
