struct RecentlyDeletedCategory: Equatable {
  let fileName: String
  let fileURL: URL
  let deletionDate: TimeInterval
}

private struct TextFiltering {
  static let empty = TextFiltering(searchText: "")

  var searchText: String

  func filter(_ category: RecentlyDeletedCategory) -> Bool {
    guard !searchText.isEmpty else { return true }
    return category.fileName.localizedCaseInsensitiveContains(searchText)
  }
}

final class RecentlyDeletedCategoriesViewModel {

  enum Section: CaseIterable {
    struct Model: Equatable {
      var categories: [RecentlyDeletedCategory]
    }

    case main
  }

  enum State {
    case normal
    case searching
    case editingAndNothingSelected
    case editingAndSomeSelected
  }

  private var bookmarksManager: any RecentlyDeletedCategoriesManager
  private(set) var selectedIndexPaths: [IndexPath] = []
  private var dataSource: [Section.Model] = []
  private(set) var filteredDataSource: [Section.Model] = []
  private(set) var state: State = .normal
  private var textFilter: TextFiltering = .empty
  var stateDidChange: ((State) -> Void)?
  var filteredDataSourceDidChange: (([Section.Model]) -> Void)?

  init(bookmarksManager: RecentlyDeletedCategoriesManager = BookmarksManager.shared()) {
    self.bookmarksManager = bookmarksManager
    fetchRecentlyDeletedCategories()
  }

  // MARK: - Private methods
  private func updateState(to newState: State) {
    guard state != newState else { return }
    state = newState
    stateDidChange?(state)
  }

  private func updateFilteredDataSource(_ dataSource: [Section.Model]) {
    filteredDataSource = dataSource.filtered(using: textFilter)
    filteredDataSourceDidChange?(filteredDataSource)
  }

  private func updateSelectionAtIndexPath(_ indexPath: IndexPath, isSelected: Bool) {
    if isSelected {
      updateState(to: .editingAndSomeSelected)
    } else {
      let allDeselected = dataSource.allSatisfy { $0.categories.isEmpty }
      updateState(to: allDeselected ? .editingAndNothingSelected : .editingAndSomeSelected)
    }
  }

  private func removeCategories(at indexPaths: [IndexPath], completion: ([URL]) -> Void) {
    var fileToRemoveURLs: [URL]
    if indexPaths.isEmpty {
      // Remove all without selection.
      fileToRemoveURLs = dataSource.flatMap { $0.categories.map { $0.fileURL } }
      dataSource.removeAll()
    } else {
      fileToRemoveURLs = [URL]()
      indexPaths.forEach { [weak self] indexPath in
        guard let self else { return }
        let fileToRemoveURL = self.filteredDataSource[indexPath.section].categories[indexPath.row].fileURL
        self.dataSource[indexPath.section].categories.removeAll { $0.fileURL == fileToRemoveURL }
        fileToRemoveURLs.append(fileToRemoveURL)
      }
    }
    updateFilteredDataSource(dataSource)
    updateState(to: .normal)
    completion(fileToRemoveURLs)
  }

  private func removeSelectedCategories(completion: ([URL]) -> Void) {
    let removeAll = selectedIndexPaths.isEmpty || selectedIndexPaths.count == dataSource.flatMap({ $0.categories }).count
    removeCategories(at: removeAll ? [] : selectedIndexPaths, completion: completion)
    selectedIndexPaths.removeAll()
    updateState(to: .normal)
  }
}

// MARK: - Public methods
extension RecentlyDeletedCategoriesViewModel {
  func fetchRecentlyDeletedCategories() {
    let recentlyDeletedCategoryURLs = bookmarksManager.getRecentlyDeletedCategories()
    let categories = recentlyDeletedCategoryURLs.map { fileUrl in
      let fileName = fileUrl.lastPathComponent
      // TODO: remove this code with cpp
      let deletionDate = (try! fileUrl.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date()).timeIntervalSince1970
      return RecentlyDeletedCategory(fileName: fileName, fileURL: fileUrl, deletionDate: deletionDate)
    }
    dataSource = [Section.Model(categories: categories)]
    updateFilteredDataSource(dataSource)
  }

  func deleteCategory(at indexPath: IndexPath) {
    removeCategories(at: [indexPath]) { bookmarksManager.deleteRecentlyDeletedCategory(at: $0) }
  }

  func deleteSelectedCategories() {
    removeSelectedCategories { bookmarksManager.deleteRecentlyDeletedCategory(at: $0) }
  }

  func recoverCategory(at indexPath: IndexPath) {
    removeCategories(at: [indexPath]) { bookmarksManager.recoverRecentlyDeletedCategories(at: $0) }
  }

  func recoverSelectedCategories() {
    removeSelectedCategories { bookmarksManager.recoverRecentlyDeletedCategories(at: $0) }
  }

  func startSelecting() {
    updateState(to: .editingAndNothingSelected)
  }

  func selectCategory(at indexPath: IndexPath) {
    selectedIndexPaths.append(indexPath)
    updateState(to: .editingAndSomeSelected)
  }

  func deselectCategory(at indexPath: IndexPath) {
    selectedIndexPaths.removeAll { $0 == indexPath }
    if selectedIndexPaths.isEmpty {
      updateState(to: .editingAndNothingSelected)
    }
  }

  func selectAllCategories() {
    selectedIndexPaths = dataSource.enumerated().flatMap { sectionIndex, section in
      section.categories.indices.map { IndexPath(row: $0, section: sectionIndex) }
    }
    updateState(to: .editingAndSomeSelected)
  }

  func deselectAllCategories() {
    selectedIndexPaths.removeAll()
    updateState(to: .editingAndNothingSelected)
  }

  func cancelSelecting() {
    selectedIndexPaths.removeAll()
    updateState(to: .normal)
  }

  func startSearching() {
    updateState(to: .searching)
  }

  func cancelSearching() {
    textFilter.searchText.removeAll()
    selectedIndexPaths.removeAll()
    updateFilteredDataSource(dataSource)
    updateState(to: .normal)
  }

  func search(_ searchText: String) {
    updateState(to: .searching)
    guard !searchText.isEmpty else {
      cancelSearching()
      return
    }
    textFilter.searchText = searchText
    updateFilteredDataSource(dataSource)
  }
}

private extension Array where Element == RecentlyDeletedCategoriesViewModel.Section.Model {
  func filtered(using filtering: TextFiltering) -> [Element]{
    let filteredArray = map { section in
      let filteredCategories = section.categories.filter { filtering.filter($0) }
      return RecentlyDeletedCategoriesViewModel.Section.Model(categories: filteredCategories)
    }
    return filteredArray
  }
}
