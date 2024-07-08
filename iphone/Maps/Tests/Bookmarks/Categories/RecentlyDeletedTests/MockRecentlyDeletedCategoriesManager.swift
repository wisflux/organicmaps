class MockRecentlyDeletedCategoriesManager: NSObject, RecentlyDeletedCategoriesManager {
  var categories = [RecentlyDeletedCellViewModel]()

  func getRecentlyDeletedCategories() -> [RecentlyDeletedCategory] {
    []
  }

  func deleteRecentlyDeletedCategory(at urls: [URL]) {
    categories.removeAll { urls.contains($0.fileURL) }
  }

  func deleteAllRecentlyDeletedCategories() {
    categories.removeAll()
  }

  func recoverRecentlyDeletedCategories(at urls: [URL]) {
    categories.removeAll { urls.contains($0.fileURL) }
  }
}
