enum VoidResult {
  case success
  case failure(Error)
}

enum WritingResult {
  case success
  case reloadCategoriesAtURLs([URL])
  case deleteCategoriesAtURLs([URL])
  case failure(Error)
}

typealias VoidResultCompletionHandler = (VoidResult) -> Void
typealias WritingResultCompletionHandler = (WritingResult) -> Void

// TODO: Remove this type and use custom UTTypeIdentifier that is registered into the Info.plist after updating to the iOS >= 14.0.
struct FileType {
  let fileExtension: String
  let typeIdentifier: String
}

extension FileType {
  static let kml = FileType(fileExtension: "kml", typeIdentifier: "com.google.earth.kml")
}

let kTrashDirectoryName = ".Trash"
private let kBookmarksDirectoryName = "bookmarks"
private let kICloudSynchronizationDidChangeEnabledStateNotificationName = "iCloudSynchronizationDidChangeEnabledStateNotification"
private let kUDDidFinishInitialCloudSynchronization = "kUDDidFinishInitialCloudSynchronization"

@objc @objcMembers final class CloudStorageManager: NSObject {

  fileprivate struct Observation {
    weak var observer: AnyObject?
    var onErrorCompletionHandler: ((NSError?) -> Void)?
  }

  let fileManager: FileManager
  private let localDirectoryMonitor: LocalDirectoryMonitor
  private let cloudDirectoryMonitor: CloudDirectoryMonitor
  private let settings: Settings.Type
  private let bookmarksManager: BookmarksManager
  private let synchronizationStateManager: SynchronizationStateManager
  private var fileWriter: SynchronizationFileWriter?
  private var observers = [ObjectIdentifier: CloudStorageManager.Observation]()
  private var synchronizationError: SynchronizationError? {
    didSet { notifyObserversOnSynchronizationError(synchronizationError) }
  }

  static private var isInitialSynchronization: Bool {
    return !UserDefaults.standard.bool(forKey: kUDDidFinishInitialCloudSynchronization)
  }

  static let shared: CloudStorageManager = {
    let fileManager = FileManager.default
    let fileType = FileType.kml
    let cloudDirectoryMonitor = iCloudDocumentsDirectoryMonitor(fileManager: fileManager, fileType: fileType)
    let synchronizationStateManager = DefaultSynchronizationStateManager(isInitialSynchronization: CloudStorageManager.isInitialSynchronization)
    do {
      let localDirectoryMonitor = try DefaultLocalDirectoryMonitor(fileManager: fileManager, directory: fileManager.bookmarksDirectoryUrl, fileType: fileType)
      let clodStorageManager = try CloudStorageManager(fileManager: fileManager,
                                                       settings: Settings.self,
                                                       bookmarksManager: BookmarksManager.shared(),
                                                       cloudDirectoryMonitor: cloudDirectoryMonitor,
                                                       localDirectoryMonitor: localDirectoryMonitor,
                                                       synchronizationStateManager: synchronizationStateManager)
      return clodStorageManager
    } catch {
      fatalError("Failed to create shared iCloud storage manager with error: \(error)")
    }
  }()

  // MARK: - Initialization
  init(fileManager: FileManager,
       settings: Settings.Type,
       bookmarksManager: BookmarksManager,
       cloudDirectoryMonitor: CloudDirectoryMonitor,
       localDirectoryMonitor: LocalDirectoryMonitor,
       synchronizationStateManager: SynchronizationStateManager) throws {
    guard fileManager === cloudDirectoryMonitor.fileManager, fileManager === localDirectoryMonitor.fileManager else {
      throw NSError(domain: "CloudStorageManger", code: 0, userInfo: [NSLocalizedDescriptionKey: "File managers should be the same."])
    }
    self.fileManager = fileManager
    self.settings = settings
    self.bookmarksManager = bookmarksManager
    self.cloudDirectoryMonitor = cloudDirectoryMonitor
    self.localDirectoryMonitor = localDirectoryMonitor
    self.synchronizationStateManager = synchronizationStateManager
    super.init()
  }

  // MARK: - Public
  @objc func start() {
    subscribeToSettingsNotifications()
    subscribeToApplicationLifecycleNotifications()
    cloudDirectoryMonitor.delegate = self
    localDirectoryMonitor.delegate = self
  }
}

// MARK: - Private
private extension CloudStorageManager {
  // MARK: - Synchronization Lifecycle
  func startSynchronization() {
    LOG(.debug, "Start synchronization...")
    switch cloudDirectoryMonitor.state {
    case .started:
      LOG(.debug, "Synchronization is already started")
      return
    case .paused:
      resumeSynchronization()
    case .stopped:
      cloudDirectoryMonitor.start { [weak self] result in
        guard let self else { return }
        switch result {
        case .failure(let error):
          self.stopSynchronization()
          self.processError(error)
        case .success(let cloudDirectoryUrl):
          self.localDirectoryMonitor.start { result in
            switch result {
            case .failure(let error):
              self.stopSynchronization()
              self.processError(error)
            case .success(let localDirectoryUrl):
              self.fileWriter = SynchronizationFileWriter(fileManager: self.fileManager,
                                                          localDirectoryUrl: localDirectoryUrl,
                                                          cloudDirectoryUrl: cloudDirectoryUrl)
              LOG(.debug, "Synchronization is started successfully")
            }
          }
        }
      }
    }
  }

  func stopSynchronization() {
    LOG(.debug, "Stop synchronization")
    localDirectoryMonitor.stop()
    cloudDirectoryMonitor.stop()
    synchronizationError = nil
    fileWriter = nil
    synchronizationStateManager.resetState()
  }

  func pauseSynchronization() {
    LOG(.debug, "Pause synchronization")
    localDirectoryMonitor.pause()
    cloudDirectoryMonitor.pause()
  }

  func resumeSynchronization() {
    LOG(.debug, "Resume synchronization")
    localDirectoryMonitor.resume()
    cloudDirectoryMonitor.resume()
  }

  // MARK: - App Lifecycle
  func subscribeToApplicationLifecycleNotifications() {
    NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.didBecomeActiveNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
  }

  func unsubscribeFromApplicationLifecycleNotifications() {
    NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
    NotificationCenter.default.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
  }

  func subscribeToSettingsNotifications() {
    NotificationCenter.default.addObserver(self, selector: #selector(didChangeEnabledState), name: NSNotification.iCloudSynchronizationDidChangeEnabledState, object: nil)
  }

  @objc func appWillEnterForeground() {
    guard settings.iCLoudSynchronizationEnabled() else { return }
    startSynchronization()
  }

  @objc func appDidEnterBackground() {
    guard settings.iCLoudSynchronizationEnabled() else { return }
    pauseSynchronization()
  }

  @objc func didChangeEnabledState() {
    settings.iCLoudSynchronizationEnabled() ? startSynchronization() : stopSynchronization()
  }
}

// MARK: - iCloudStorageManger + LocalDirectoryMonitorDelegate
extension CloudStorageManager: LocalDirectoryMonitorDelegate {
  func didFinishGathering(contents: LocalContents) {
    let events = synchronizationStateManager.resolveEvent(.didFinishGatheringLocalContents(contents))
    processEvents(events)
  }

  func didUpdate(contents: LocalContents) {
    let events = synchronizationStateManager.resolveEvent(.didUpdateLocalContents(contents))
    processEvents(events)
  }

  func didReceiveLocalMonitorError(_ error: Error) {
    processError(error)
  }
}

// MARK: - iCloudStorageManger + CloudDirectoryMonitorDelegate
extension CloudStorageManager: CloudDirectoryMonitorDelegate {
  func didFinishGathering(contents: CloudContents) {
    let events = synchronizationStateManager.resolveEvent(.didFinishGatheringCloudContents(contents))
    processEvents(events)
  }

  func didUpdate(contents: CloudContents) {
    let events = synchronizationStateManager.resolveEvent(.didUpdateCloudContents(contents))
    processEvents(events)
  }

  func didReceiveCloudMonitorError(_ error: Error) {
    processError(error)
  }
}

// MARK: - Private methods
private extension CloudStorageManager {
  func processEvents(_ events: [OutgoingEvent]) {
    guard !events.isEmpty else {
      synchronizationError = nil
      return
    }

    LOG(.debug, "Start processing events...")
    events.forEach { [weak self] event in
      LOG(.debug, "Processing event: \(event)")
      guard let self, let fileWriter else { return }
      fileWriter.processEvent(event, completion: writingResultHandler(for: event))
    }
  }

  func writingResultHandler(for event: OutgoingEvent) -> WritingResultCompletionHandler {
    return { [weak self] result in
      guard let self else { return }
      DispatchQueue.main.async {
        switch result {
        case .success:
          // Mark that initial synchronization is finished.
          if case .didFinishInitialSynchronization = event {
            UserDefaults.standard.set(true, forKey: kUDDidFinishInitialCloudSynchronization)
          }
        case .reloadCategoriesAtURLs(let urls):
          urls.forEach { self.bookmarksManager.reloadCategory(atFilePath: $0.path) }
        case .deleteCategoriesAtURLs(let urls):
          urls.forEach { self.bookmarksManager.deleteCategory(atFilePath: $0.path) }
        case .failure(let error):
          self.processError(error)
        }
      }
    }
  }

  // MARK: - Error handling
  func processError(_ error: Error) {
    if let synchronizationError = error as? SynchronizationError {
      LOG(.debug, "Synchronization error: \(error.localizedDescription)")
      switch synchronizationError {
      case .fileUnavailable: break
      case .fileNotUploadedDueToQuota: break
      case .ubiquityServerNotAvailable: break
      case .iCloudIsNotAvailable: fallthrough
      case .failedToOpenLocalDirectoryFileDescriptor: fallthrough
      case .failedToRetrieveLocalDirectoryContent: fallthrough
      case .containerNotFound:
        stopSynchronization()
      }
      self.synchronizationError = synchronizationError
    } else {
      // TODO: Handle non-synchronization errors
      LOG(.debug, "Non-synchronization error: \(error.localizedDescription)")
    }
  }
}

// MARK: - CloudStorageManger Observing
extension CloudStorageManager {
  func addObserver(_ observer: AnyObject, onErrorCompletionHandler: @escaping (NSError?) -> Void) {
    let id = ObjectIdentifier(observer)
    observers[id] = Observation(observer: observer, onErrorCompletionHandler:onErrorCompletionHandler)
    // Notify the new observer immediately to handle initial state.
    observers[id]?.onErrorCompletionHandler?(synchronizationError as NSError?)
  }

  func removeObserver(_ observer: AnyObject) {
    let id = ObjectIdentifier(observer)
    observers.removeValue(forKey: id)
  }

  private func notifyObserversOnSynchronizationError(_ error: SynchronizationError?) {
    self.observers.removeUnreachable().forEach { _, observable in
      DispatchQueue.main.async {
        observable.onErrorCompletionHandler?(error as NSError?)
      }
    }
  }
}

// MARK: - FileManager + Directories
extension FileManager {
  var bookmarksDirectoryUrl: URL {
    urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent(kBookmarksDirectoryName, isDirectory: true)
  }

  func trashDirectoryUrl(for baseDirectoryUrl: URL) throws -> URL {
    let trashDirectory = baseDirectoryUrl.appendingPathComponent(kTrashDirectoryName, isDirectory: true)
    if !fileExists(atPath: trashDirectory.path) {
      try createDirectory(at: trashDirectory, withIntermediateDirectories: true)
    }
    return trashDirectory
  }
}

// MARK: - Notification + iCloudSynchronizationDidChangeEnabledState
extension Notification.Name {
  static let iCloudSynchronizationDidChangeEnabledStateNotification = Notification.Name(kICloudSynchronizationDidChangeEnabledStateNotificationName)
}

@objc extension NSNotification {
  public static let iCloudSynchronizationDidChangeEnabledState = Notification.Name.iCloudSynchronizationDidChangeEnabledStateNotification
}

// MARK: - URL + ResourceValues
private extension URL {
  func setResourceModificationDate(_ date: Date) throws {
    var url = self
    var resource = try resourceValues(forKeys:[.contentModificationDateKey])
    resource.contentModificationDate = date
    try url.setResourceValues(resource)
  }
}

private extension Data {
  func write(to url: URL, options: Data.WritingOptions = .atomic, lastModificationDate: TimeInterval? = nil) throws {
    var url = url
    try write(to: url, options: options)
    if let lastModificationDate {
      try url.setResourceModificationDate(Date(timeIntervalSince1970: lastModificationDate))
    }
  }
}

// MARK: - Dictionary + RemoveUnreachable
private extension Dictionary where Key == ObjectIdentifier, Value == CloudStorageManager.Observation {
  mutating func removeUnreachable() -> Self {
    for (id, observation) in self {
      if observation.observer == nil {
        removeValue(forKey: id)
      }
    }
    return self
  }
}

final class SynchronizationFileWriter {
  private let fileManager: FileManager
  private let backgroundQueue = DispatchQueue(label: "iCloud.app.organicmaps.backgroundQueue", qos: .background)
  private let fileCoordinator: NSFileCoordinator
  private let localDirectoryUrl: URL
  private let cloudDirectoryUrl: URL

  init(fileManager: FileManager = .default, 
       fileCoordinator: NSFileCoordinator = NSFileCoordinator(),
       localDirectoryUrl: URL,
       cloudDirectoryUrl: URL) {
    self.fileManager = fileManager
    self.fileCoordinator = fileCoordinator
    self.localDirectoryUrl = localDirectoryUrl
    self.cloudDirectoryUrl = cloudDirectoryUrl
  }

  func processEvent(_ event: OutgoingEvent, completion: @escaping WritingResultCompletionHandler) {
    backgroundQueue.async { [weak self] in
      guard let self else { return }
      switch event {
      case .createLocalItem(let cloudMetadataItem): self.createInLocalContainer(cloudMetadataItem, completion: completion)
      case .updateLocalItem(let cloudMetadataItem): self.updateInLocalContainer(cloudMetadataItem, completion: completion)
      case .removeLocalItem(let cloudMetadataItem): self.removeFromLocalContainer(cloudMetadataItem, completion: completion)
      case .startDownloading(let cloudMetadataItem): self.startDownloading(cloudMetadataItem, completion: completion)
      case .createCloudItem(let localMetadataItem): self.createInCloudContainer(localMetadataItem, completion: completion)
      case .updateCloudItem(let localMetadataItem): self.updateInCloudContainer(localMetadataItem, completion: completion)
      case .removeCloudItem(let localMetadataItem): self.removeFromCloudContainer(localMetadataItem, completion: completion)
      case .resolveVersionsConflict(let cloudMetadataItem): self.resolveVersionsConflict(cloudMetadataItem, completion: completion)
      case .resolveInitialSynchronizationConflict(let localMetadataItem): self.resolveInitialSynchronizationConflict(localMetadataItem, completion: completion)
      case .didFinishInitialSynchronization: completion(.success)
      case .didReceiveError(let error): completion(.failure(error))
      }
    }
  }

  // MARK: - Read/Write/Downloading/Uploading
  private func startDownloading(_ cloudMetadataItem: CloudMetadataItem, completion: WritingResultCompletionHandler) {
    do {
      LOG(.debug, "Start downloading file: \(cloudMetadataItem.fileName)...")
      try fileManager.startDownloadingUbiquitousItem(at: cloudMetadataItem.fileUrl)
      completion(.success)
    } catch {
      completion(.failure(error))
    }
  }

  private func createInLocalContainer(_ cloudMetadataItem: CloudMetadataItem, completion: @escaping WritingResultCompletionHandler) {
    let targetLocalFileUrl = cloudMetadataItem.relatedLocalItemUrl(to: localDirectoryUrl)
    guard !fileManager.fileExists(atPath: targetLocalFileUrl.path) else {
      LOG(.debug, "File \(cloudMetadataItem.fileName) already exists in the local iCloud container.")
      completion(.success)
      return
    }
    writeToLocalContainer(cloudMetadataItem, completion: completion)
  }

  private func updateInLocalContainer(_ cloudMetadataItem: CloudMetadataItem, completion: @escaping WritingResultCompletionHandler) {
    writeToLocalContainer(cloudMetadataItem, completion: completion)
  }

  private func writeToLocalContainer(_ cloudMetadataItem: CloudMetadataItem, completion: @escaping WritingResultCompletionHandler) {
    var coordinationError: NSError?
    let targetLocalFileUrl = cloudMetadataItem.relatedLocalItemUrl(to: localDirectoryUrl)
    LOG(.debug, "File \(cloudMetadataItem.fileName) is downloaded to the local iCloud container. Start coordinating and writing file...")
    fileCoordinator.coordinate(readingItemAt: cloudMetadataItem.fileUrl, writingItemAt: targetLocalFileUrl, error: &coordinationError) { readingUrl, writingUrl in
      do {
        let cloudFileData = try Data(contentsOf: readingUrl)
        try cloudFileData.write(to: writingUrl, options: .atomic, lastModificationDate: cloudMetadataItem.lastModificationDate)
        LOG(.debug, "File \(cloudMetadataItem.fileName) is copied to local directory successfully. Start reloading bookmarks...")
        completion(.reloadCategoriesAtURLs([writingUrl]))
      } catch {
        completion(.failure(error))
      }
      return
    }
    if let coordinationError {
      completion(.failure(coordinationError))
    }
  }

  private func removeFromLocalContainer(_ cloudMetadataItem: CloudMetadataItem, completion: @escaping WritingResultCompletionHandler) {
    LOG(.debug, "Start removing file \(cloudMetadataItem.fileName) from the local directory...")
    let targetLocalFileUrl = cloudMetadataItem.relatedLocalItemUrl(to: localDirectoryUrl)
    guard fileManager.fileExists(atPath: targetLocalFileUrl.path) else {
      LOG(.debug, "File \(cloudMetadataItem.fileName) doesn't exist in the local directory and cannot be removed.")
      completion(.success)
      return
    }
    completion(.deleteCategoriesAtURLs([targetLocalFileUrl]))
    LOG(.debug, "File \(cloudMetadataItem.fileName) is removed from the local directory successfully.")
  }

  private func createInCloudContainer(_ localMetadataItem: LocalMetadataItem, completion: @escaping WritingResultCompletionHandler) {
    let targetCloudFileUrl = localMetadataItem.relatedCloudItemUrl(to: cloudDirectoryUrl)
    guard !fileManager.fileExists(atPath: targetCloudFileUrl.path) else {
      LOG(.debug, "File \(localMetadataItem.fileName) already exists in the cloud directory.")
      completion(.success)
      return
    }
    writeToCloudContainer(localMetadataItem, completion: completion)
  }

  private func updateInCloudContainer(_ localMetadataItem: LocalMetadataItem, completion: @escaping WritingResultCompletionHandler) {
    writeToCloudContainer(localMetadataItem, completion: completion)
  }

  private func writeToCloudContainer(_ localMetadataItem: LocalMetadataItem, completion: @escaping WritingResultCompletionHandler) {
    LOG(.debug, "Start writing file \(localMetadataItem.fileName) to the cloud directory...")
    let targetCloudFileUrl = localMetadataItem.relatedCloudItemUrl(to: cloudDirectoryUrl)
    var coordinationError: NSError?
    fileCoordinator.coordinate(readingItemAt: localMetadataItem.fileUrl, writingItemAt: targetCloudFileUrl, error: &coordinationError) { readingUrl, writingUrl in
      do {
        let fileData = try localMetadataItem.fileData()
        try fileData.write(to: writingUrl, lastModificationDate: localMetadataItem.lastModificationDate)
        LOG(.debug, "File \(localMetadataItem.fileName) is copied to the cloud directory successfully.")
        completion(.success)
      } catch {
        completion(.failure(error))
      }
      return
    }
    if let coordinationError {
      completion(.failure(coordinationError))
    }
  }

  private func removeFromCloudContainer(_ localMetadataItem: LocalMetadataItem, completion: @escaping WritingResultCompletionHandler) {
    LOG(.debug, "Start trashing file \(localMetadataItem.fileName)...")
    do {
      let targetCloudFileUrl = localMetadataItem.relatedCloudItemUrl(to: cloudDirectoryUrl)
      try removeDuplicatedFileFromTrashDirectoryIfNeeded(cloudDirectoryUrl: cloudDirectoryUrl, fileName: localMetadataItem.fileName)
      try self.fileManager.trashItem(at: targetCloudFileUrl, resultingItemURL: nil)
      LOG(.debug, "File \(localMetadataItem.fileName) was trashed successfully.")
      completion(.success)
    } catch {
      completion(.failure(error))
    }
  }

  // Remove duplicated file from iCloud's .Trash directory if needed.
  // It's important to avoid the duplicating of names in the trash because we can't control the name of the trashed item.
  private func removeDuplicatedFileFromTrashDirectoryIfNeeded(cloudDirectoryUrl: URL, fileName: String) throws {
    // There are no ways to retrieve the content of iCloud's .Trash directory on macOS.
    if #available(iOS 14.0, *), ProcessInfo.processInfo.isiOSAppOnMac {
      return
    }
    LOG(.debug, "Checking if the file \(fileName) is already in the trash directory...")
    let trashDirectoryUrl = try fileManager.trashDirectoryUrl(for: cloudDirectoryUrl)
    let fileInTrashDirectoryUrl = trashDirectoryUrl.appendingPathComponent(fileName)
    let trashDirectoryContent = try fileManager.contentsOfDirectory(at: trashDirectoryUrl,
                                                                    includingPropertiesForKeys: [],
                                                                    options: [.skipsPackageDescendants, .skipsSubdirectoryDescendants])
    if trashDirectoryContent.contains(fileInTrashDirectoryUrl) {
      LOG(.debug, "File \(fileName) is already in the trash directory. Removing it...")
      try fileManager.removeItem(at: fileInTrashDirectoryUrl)
      LOG(.debug, "File \(fileName) was removed from the trash directory successfully.")
    }
  }

  // MARK: - Merge conflicts resolving
  private func resolveVersionsConflict(_ cloudMetadataItem: CloudMetadataItem, completion: @escaping WritingResultCompletionHandler) {
    LOG(.debug, "Start resolving version conflict for file \(cloudMetadataItem.fileName)...")

    guard let versionsInConflict = NSFileVersion.unresolvedConflictVersionsOfItem(at: cloudMetadataItem.fileUrl), !versionsInConflict.isEmpty,
          let currentVersion = NSFileVersion.currentVersionOfItem(at: cloudMetadataItem.fileUrl) else {
      LOG(.debug, "No versions in conflict found for file \(cloudMetadataItem.fileName).")
      completion(.success)
      return
    }

    let sortedVersions = versionsInConflict.sorted { version1, version2 in
      guard let date1 = version1.modificationDate, let date2 = version2.modificationDate else {
        return false
      }
      return date1 > date2
    }

    guard let latestVersionInConflict = sortedVersions.first else {
      LOG(.debug, "No latest version in conflict found for file \(cloudMetadataItem.fileName).")
      completion(.success)
      return
    }

    let targetCloudFileCopyUrl = generateNewFileUrl(for: cloudMetadataItem.fileUrl)
    var coordinationError: NSError?
    fileCoordinator.coordinate(writingItemAt: currentVersion.url,
                               options: [.forReplacing],
                               writingItemAt: targetCloudFileCopyUrl,
                               options: [],
                               error: &coordinationError) { currentVersionUrl, copyVersionUrl in
      // Check that during the coordination block, the current version of the file have not been already resolved by another process.
      guard let unresolvedVersions = NSFileVersion.unresolvedConflictVersionsOfItem(at: currentVersionUrl), !unresolvedVersions.isEmpty else {
        LOG(.debug, "File \(cloudMetadataItem.fileName) was already resolved.")
        completion(.success)
        return
      }
      do {
        // Check if the file was already resolved by another process. The in-memory versions should be marked as resolved.
        guard !fileManager.fileExists(atPath: copyVersionUrl.path) else {
          LOG(.debug, "File \(cloudMetadataItem.fileName) was already resolved.")
          try NSFileVersion.removeOtherVersionsOfItem(at: currentVersionUrl)
          completion(.success)
          return
        }
        
        LOG(.debug, "Duplicate file \(cloudMetadataItem.fileName)...")
        try latestVersionInConflict.replaceItem(at: copyVersionUrl)
        // The modification date should be updated to mark files that was involved into the resolving process.
        try currentVersionUrl.setResourceModificationDate(Date())
        try copyVersionUrl.setResourceModificationDate(Date())
        unresolvedVersions.forEach { $0.isResolved = true }
        try NSFileVersion.removeOtherVersionsOfItem(at: currentVersionUrl)
        LOG(.debug, "File \(cloudMetadataItem.fileName) was successfully resolved.")
        completion(.success)
        return
      } catch {
        completion(.failure(error))
        return
      }
    }

    if let coordinationError {
      completion(.failure(coordinationError))
    }
  }

  private func resolveInitialSynchronizationConflict(_ localMetadataItem: LocalMetadataItem, completion: @escaping WritingResultCompletionHandler) {
    LOG(.debug, "Start resolving initial sync conflict for file \(localMetadataItem.fileName) by copying with a new name...")
    do {
      let newFileUrl = generateNewFileUrl(for: localMetadataItem.fileUrl, addDeviceName: true)
      try fileManager.copyItem(at: localMetadataItem.fileUrl, to: newFileUrl)
      LOG(.debug, "File \(localMetadataItem.fileName) was successfully resolved.")
      completion(.reloadCategoriesAtURLs([newFileUrl]))
    } catch {
      completion(.failure(error))
    }
  }

  // MARK: - Helper methods
  // Generate a new file URL with a new name for the file with the same name.
  // This method should generate the same name for the same file on different devices during the simultaneous conflict resolving.
  private func generateNewFileUrl(for fileUrl: URL, addDeviceName: Bool = false) -> URL {
    let baseName = fileUrl.deletingPathExtension().lastPathComponent
    let fileExtension = fileUrl.pathExtension
    let newBaseName = baseName + "_1"
    let deviceName = addDeviceName ? "_\(UIDevice.current.name)" : ""
    let newFileName = newBaseName + deviceName + "." + fileExtension
    let newFileUrl = fileUrl.deletingLastPathComponent().appendingPathComponent(newFileName)
    return newFileUrl
  }
}
