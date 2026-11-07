import Darwin
import Flutter
import Metal
import Photos
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Touch the downloads singleton at every launch — including the
    // system relaunch for background-session events — so its session
    // reattaches to any transfers the daemon kept running (ticket 05).
    _ = MiniXDownloads.shared
    // Ticket 23: clear any Live Activity the previous process
    // left behind; live transfers recreate theirs on progress.
    MiniXLiveActivity.shared.endAllStale()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    MiniXDownloads.shared.bgCompletionHandler = completionHandler
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Diagnostics channel (MiniX ticket 01): exposes
    // os_proc_available_memory() — the figure iOS jetsam decisions are
    // made against — to the Dart MemoryProbe. Ticket 22 adds `sample`
    // (the telemetry series) and `diskFreeBytes` (the ticket 05
    // pre-download fit check) on the same channel.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MiniXDiagnostics") {
      let channel = FlutterMethodChannel(
        name: "minix/diagnostics",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "availableMemoryBytes":
          result(os_proc_available_memory())
        case "diskFreeBytes":
          result(MiniXSampler.diskFreeBytes())
        case "sample":
          result(MiniXSampler.sample())
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    // Downloads channel (MiniX ticket 05): the Dart side starts,
    // cancels and polls the native background URLSession owned by
    // MiniXDownloads. Transfers survive the app being suspended or
    // killed because the system daemon performs them.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MiniXDownloads") {
      let channel = FlutterMethodChannel(
        name: "minix/downloads",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { call, result in
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "start":
          guard let url = args["url"] as? String,
                let filename = args["filename"] as? String,
                let destDir = args["destDir"] as? String,
                let name = args["name"] as? String else {
            result(FlutterError(code: "bad_args", message: "start needs url, filename, destDir, name", details: nil))
            return
          }
          MiniXDownloads.shared.start(filename: filename, urlString: url, destDir: destDir, displayName: name)
          result(true)
        case "cancel":
          if let filename = args["filename"] as? String {
            MiniXDownloads.shared.cancel(filename: filename)
          }
          result(true)
        case "status":
          if let filename = args["filename"] as? String {
            result(MiniXDownloads.shared.status(filename: filename))
          } else {
            result(["status": "none"])
          }
        case "allStatuses":
          result(MiniXDownloads.shared.allStatuses())
        case "ack":
          if let filename = args["filename"] as? String {
            MiniXDownloads.shared.ack(filename: filename)
          }
          result(true)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    // Media channel (1.20.9): Save-to-Photos for the gallery viewer.
    // Add-only Photos authorization (NSPhotoLibraryAddUsageDescription
    // is already in Info.plist); the file stays in app storage either
    // way, this only writes a copy into the user's photo library.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MiniXMedia") {
      let channel = FlutterMethodChannel(
        name: "minix/media",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "saveToPhotos":
          let args = call.arguments as? [String: Any] ?? [:]
          guard let path = args["path"] as? String else {
            result(FlutterError(code: "bad_args", message: "saveToPhotos needs path", details: nil))
            return
          }
          MiniXMedia.save(path: path, isVideo: args["isVideo"] as? Bool ?? false, result: result)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}

// ── Media save (1.20.9) ────────────────────────────────────────
enum MiniXMedia {
  static func save(path: String, isVideo: Bool, result: @escaping FlutterResult) {
    let url = URL(fileURLWithPath: path)
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
      guard status == .authorized || status == .limited else {
        DispatchQueue.main.async {
          result(FlutterError(code: "denied", message: "Photo library access is not granted", details: nil))
        }
        return
      }
      PHPhotoLibrary.shared().performChanges({
        if isVideo {
          PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        } else {
          PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
        }
      }) { ok, error in
        DispatchQueue.main.async {
          if ok {
            result(true)
          } else {
            result(FlutterError(code: "save_failed", message: error?.localizedDescription, details: nil))
          }
        }
      }
    }
  }
}

// ── Telemetry sampler (ticket 22) ──────────────────────────────
// One sample = the honest iOS proxy set: jetsam headroom, the app's
// own footprint, instantaneous CPU (100% = one core, Claude UPDATE 3
// scaling), major page faults per second (flash reads — the decisive
// field for whether the 26B is I/O-bound), thermal state, battery,
// and Metal's allocated bytes on the system default device. GPU
// utilisation % is not exposed to third-party apps and is never
// invented here.
final class MiniXSampler {
  private static var prevMajflt: Int?
  private static var prevMajfltAt: Date?

  static func sample() -> [String: Any] {
    // Major page faults + rate since the previous sample.
    var ru = rusage()
    getrusage(RUSAGE_SELF, &ru)
    let majflt = Int(ru.ru_majflt)
    let now = Date()
    var majfltPerSec = 0.0
    if let prev = prevMajflt, let prevAt = prevMajfltAt {
      let dt = now.timeIntervalSince(prevAt)
      if dt > 0 { majfltPerSec = Double(majflt - prev) / dt }
    }
    prevMajflt = majflt
    prevMajfltAt = now

    // Instantaneous CPU: sum of per-thread cpu_usage (TH_USAGE_SCALE
    // = 100% of one core per thread), expressed so 100 = one core.
    var cpuPct = 0.0
    var threadList: thread_act_array_t?
    var threadCount: mach_msg_type_number_t = 0
    if task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS,
       let list = threadList {
      for i in 0..<Int(threadCount) {
        var info = thread_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
          ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            thread_info(list[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
          }
        }
        if kr == KERN_SUCCESS {
          cpuPct += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
        }
      }
      vm_deallocate(
        mach_task_self_,
        vm_address_t(UInt(bitPattern: list)),
        vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_act_t>.stride)
      )
    }

    // App memory footprint (task_vm_info phys_footprint).
    var footprint = -1
    var vmInfo = task_vm_info_data_t()
    var vmCount = mach_msg_type_number_t(
      MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let vmKr = withUnsafeMutablePointer(to: &vmInfo) { ptr in
      ptr.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &vmCount)
      }
    }
    if vmKr == KERN_SUCCESS { footprint = Int(vmInfo.phys_footprint) }

    UIDevice.current.isBatteryMonitoringEnabled = true
    let mtlAlloc = MTLCreateSystemDefaultDevice()?.currentAllocatedSize ?? -1

    return [
      "headroomBytes": os_proc_available_memory(),
      "footprintBytes": footprint,
      "cpuPct": cpuPct,
      "majfltPerSec": majfltPerSec,
      "thermal": ProcessInfo.processInfo.thermalState.rawValue,
      "batteryLevel": Double(UIDevice.current.batteryLevel),
      "batteryState": UIDevice.current.batteryState.rawValue,
      "mtlAllocBytes": mtlAlloc,
      "diskFreeBytes": diskFreeBytes(),
    ]
  }

  static func diskFreeBytes() -> Int {
    // volumeAvailableCapacityForImportantUsage is the figure Settings
    // shows (it counts purgeable space iOS can reclaim for the user).
    // The raw systemFreeSize under-reported by ~35 GB on the founder's
    // phone and poisoned the ticket 05 fit check (fixed in 1.8.0).
    let home = URL(fileURLWithPath: NSHomeDirectory())
    if let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
       let capacity = values.volumeAvailableCapacityForImportantUsage {
      return Int(capacity)
    }
    let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
    if let free = attrs?[.systemFreeSize] as? NSNumber {
      return free.intValue
    }
    return -1
  }
}

// ── Downloads (tickets 05 + 27: the hybrid engine) ────────────
// Two URLSessions own one transfer at a time. While MiniX is in the
// foreground the transfer runs on a plain foreground session at full
// speed; when the app leaves, the task is cancelled WITH resume data
// and immediately re-created inside the background session, which the
// system daemon keeps running while MiniX is suspended or not running
// at all (and relaunches the app to deliver events). Returning to the
// foreground swaps it back. State lives in UserDefaults so it survives
// relaunches; the finished file is moved into the models directory
// synchronously in the delegate callback (the temp file is deleted
// when that callback returns), and the started/completion/failure
// notifications are posted natively — they never depend on the Dart
// side being alive.
final class MiniXDownloads: NSObject, URLSessionDownloadDelegate, UNUserNotificationCenterDelegate {
  static let shared = MiniXDownloads()

  private var session: URLSession!
  private var fgSession: URLSession!
  private var tasks: [String: URLSessionDownloadTask] = [:]
  private var taskOwner: [String: Bool] = [:] // filename -> owned by background session
  private var swapping: Set<String> = []
  private var lastWrite: [String: Date] = [:]
  var bgCompletionHandler: (() -> Void)?

  private let statusKey = "minix.dl.status"
  private let metaKey = "minix.dl.meta"
  private let defaults = UserDefaults.standard

  override init() {
    super.init()
    let config = URLSessionConfiguration.background(withIdentifier: "com.seven.portableai.downloads")
    config.sessionSendsLaunchEvents = true
    config.isDiscretionary = false
    session = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue())
    fgSession = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue())
    UNUserNotificationCenter.current().delegate = self
    // Hybrid swaps ride the app lifecycle.
    NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground),
                                           name: UIApplication.didEnterBackgroundNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground),
                                           name: UIApplication.willEnterForegroundNotification, object: nil)
    // Reattach to transfers the daemon kept running while we were gone,
    // then reconcile: any transfer the store calls "downloading" with no
    // live task on either session is stranded (process death mid-swap or
    // while holding the foreground task) and gets revived, never left
    // sitting as a frozen zombie.
    let group = DispatchGroup()
    group.enter()
    reattach(session, background: true) { group.leave() }
    group.enter()
    reattach(fgSession, background: false) { group.leave() }
    group.notify(queue: .main) { [weak self] in self?.reconcile() }
  }

  private func reattach(_ s: URLSession, background: Bool, done: @escaping () -> Void) {
    s.getAllTasks { [weak self] all in
      guard let self = self else { done(); return }
      let meta = self.allMeta()
      for task in all {
        if let filename = meta.first(where: { $0.value["taskId"] as? Int == task.taskIdentifier })?.key,
           let dl = task as? URLSessionDownloadTask {
          self.tasks[filename] = dl
          self.taskOwner[filename] = background
          // Refresh the store with the task's LIVE byte counts so the
          // UI never shows a stale snapshot for a live transfer.
          if self.allStatus()[filename]?["status"] as? String == "downloading" {
            self.setStatus(filename, [
              "status": "downloading",
              "received": Int(dl.countOfBytesReceived),
              "total": Int(dl.countOfBytesExpectedToReceive),
            ])
          }
        }
      }
      done()
    }
  }

  /// Revive transfers the store believes are downloading but no live
  /// task backs (1.8.1). Resume data first, the stored URL as fallback;
  /// the session follows a persisted swap intent when one exists, else
  /// the current app state. A transfer with neither becomes an honest
  /// failure on screen instead of a frozen zombie.
  private func reconcile() {
    let statuses = allStatus()
    for (filename, meta) in allMeta() {
      guard statuses[filename]?["status"] as? String == "downloading",
            tasks[filename] == nil else { continue }
      let toBackground: Bool
      if let intent = meta["swapTo"] as? String {
        toBackground = intent == "bg"
      } else {
        toBackground = UIApplication.shared.applicationState != .active
      }
      let target: URLSession = toBackground ? session : fgSession
      let task: URLSessionDownloadTask
      if let resumeData = defaults.data(forKey: "minix.dl.resume.\(filename)") {
        task = target.downloadTask(withResumeData: resumeData)
        defaults.removeObject(forKey: "minix.dl.resume.\(filename)")
      } else if let urlString = meta["url"] as? String, let url = URL(string: urlString) {
        task = target.downloadTask(with: url)
      } else {
        setStatus(filename, ["status": "failed", "received": 0, "total": 0,
                             "error": "Download was interrupted and cannot resume."])
        continue
      }
      tasks[filename] = task
      taskOwner[filename] = toBackground
      var m = meta
      m["taskId"] = task.taskIdentifier
      m["owner"] = toBackground ? "bg" : "fg"
      m.removeValue(forKey: "swapTo")
      setMeta(filename, m)
      task.resume()
    }
  }

  // ── Store helpers (UserDefaults, plist-safe values only) ─────
  private func allStatus() -> [String: [String: Any]] {
    return defaults.dictionary(forKey: statusKey) as? [String: [String: Any]] ?? [:]
  }
  private func setStatus(_ filename: String, _ value: [String: Any]?) {
    var all = allStatus()
    if let value = value { all[filename] = value } else { all.removeValue(forKey: filename) }
    defaults.set(all, forKey: statusKey)
  }
  private func allMeta() -> [String: [String: Any]] {
    return defaults.dictionary(forKey: metaKey) as? [String: [String: Any]] ?? [:]
  }
  private func setMeta(_ filename: String, _ value: [String: Any]?) {
    var all = allMeta()
    if let value = value { all[filename] = value } else { all.removeValue(forKey: filename) }
    defaults.set(all, forKey: metaKey)
  }

  // ── Channel API ──────────────────────────────────────────────
  func start(filename: String, urlString: String, destDir: String, displayName: String) {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    guard let url = URL(string: urlString) else {
      setStatus(filename, ["status": "failed", "received": 0, "total": 0, "error": "Bad URL"])
      return
    }
    // Hybrid: foreground session while the app is active (full speed),
    // background session otherwise (survival).
    let toBackground = UIApplication.shared.applicationState != .active
    let owner: URLSession = toBackground ? session : fgSession
    let task: URLSessionDownloadTask
    if let resumeData = defaults.data(forKey: "minix.dl.resume.\(filename)") {
      task = owner.downloadTask(withResumeData: resumeData)
      defaults.removeObject(forKey: "minix.dl.resume.\(filename)")
    } else {
      task = owner.downloadTask(with: url)
    }
    tasks[filename] = task
    taskOwner[filename] = toBackground
    setMeta(filename, ["destDir": destDir, "name": displayName, "taskId": task.taskIdentifier,
                       "url": urlString, "owner": toBackground ? "bg" : "fg"])
    // Belt for the relaunch path: if task identifiers ever fail to
    // match after a system relaunch, the finish delegate can still
    // place the file from the request URL + this last destination.
    defaults.set(destDir, forKey: "minix.dl.lastDestDir")
    setStatus(filename, ["status": "downloading", "received": 0, "total": 0])
    task.resume()
    postStartedNotification(name: displayName)
    MiniXLiveActivity.shared.started(filename: filename, name: displayName)
  }

  func cancel(filename: String) {
    MiniXLiveActivity.shared.finished(filename: filename, ok: false, cancelled: true)
    tasks[filename]?.cancel()
    tasks.removeValue(forKey: filename)
    taskOwner.removeValue(forKey: filename)
    swapping.remove(filename)
    setStatus(filename, nil)
    setMeta(filename, nil)
    defaults.removeObject(forKey: "minix.dl.resume.\(filename)")
  }

  func status(filename: String) -> [String: Any] {
    return allStatus()[filename] ?? ["status": "none"]
  }

  func allStatuses() -> [String: [String: Any]] {
    return allStatus()
  }

  func ack(filename: String) {
    setStatus(filename, nil)
    setMeta(filename, nil)
  }

  // ── Hybrid swaps (ticket 27) ─────────────────────────────────
  @objc private func appDidEnterBackground() { swapAll(toBackground: true) }
  @objc private func appWillEnterForeground() { swapAll(toBackground: false) }

  private func swapAll(toBackground: Bool) {
    for filename in Array(tasks.keys) {
      swap(filename, toBackground: toBackground)
    }
  }

  /// Cancel the owning task WITH resume data and re-create the
  /// transfer in the other session from where it left off. If the
  /// session produces no resume data, fall back to a fresh task from
  /// the stored URL rather than losing the download outright.
  private func swap(_ filename: String, toBackground: Bool) {
    guard let task = tasks[filename],
          taskOwner[filename] != toBackground,
          !swapping.contains(filename) else { return }
    swapping.insert(filename)
    // Persist the swap intent BEFORE canceling: if the process is
    // suspended or killed mid-handoff, reconcile() at the next launch
    // revives the transfer into the intended session.
    if var m = allMeta()[filename] {
      m["swapTo"] = toBackground ? "bg" : "fg"
      setMeta(filename, m)
    }
    task.cancel(byProducingResumeData: { [weak self] data in
      guard let self = self else { return }
      let target: URLSession = toBackground ? self.session : self.fgSession
      let meta = self.allMeta()[filename]
      let newTask: URLSessionDownloadTask
      if let data = data {
        newTask = target.downloadTask(withResumeData: data)
      } else if let urlString = meta?["url"] as? String, let url = URL(string: urlString) {
        newTask = target.downloadTask(with: url)
      } else {
        self.swapping.remove(filename)
        return
      }
      self.tasks[filename] = newTask
      self.taskOwner[filename] = toBackground
      if var m = meta {
        m["taskId"] = newTask.taskIdentifier
        m["owner"] = toBackground ? "bg" : "fg"
        m.removeValue(forKey: "swapTo")
        self.setMeta(filename, m)
      }
      newTask.resume()
      self.swapping.remove(filename)
    })
  }

  /// True when this callback belongs to a task a hybrid swap has
  /// already replaced — its events must not touch the stores. A task
  /// the stores do not know at all is NOT stale: the relaunch
  /// fallback in the finish delegate decides for those.
  private func isStale(_ task: URLSessionTask) -> Bool {
    guard let filename = filename(for: task) else { return false }
    if swapping.contains(filename) { return true }
    if let current = tasks[filename] { return current !== task }
    return false
  }

  // ── URLSessionDownloadDelegate ───────────────────────────────
  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                  didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                  totalBytesExpectedToWrite: Int64) {
    guard let filename = filename(for: downloadTask) else { return }
    if isStale(downloadTask) { return }
    let now = Date()
    if let last = lastWrite[filename], now.timeIntervalSince(last) < 0.5 { return }
    lastWrite[filename] = now
    setStatus(filename, [
      "status": "downloading",
      "received": Int(totalBytesWritten),
      "total": Int(totalBytesExpectedToWrite),
    ])
    MiniXLiveActivity.shared.progress(
      filename: filename,
      received: totalBytesWritten, total: totalBytesExpectedToWrite)
  }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                  didFinishDownloadingTo location: URL) {
    if isStale(downloadTask) { return }
    let meta = filename(for: downloadTask).flatMap { allMeta()[$0] }
    let fname: String
    let destDir: String
    let name: String
    if let fn = filename(for: downloadTask), let m = meta,
       let dd = m["destDir"] as? String, let nm = m["name"] as? String {
      fname = fn
      destDir = dd
      name = nm
    } else if let urlName = downloadTask.originalRequest?.url?.lastPathComponent,
              urlName.hasSuffix(".gguf"),
              let dd = defaults.string(forKey: "minix.dl.lastDestDir") {
      // Relaunch fallback: identify the transfer by its request URL.
      fname = urlName
      destDir = dd
      name = urlName
    } else {
      return
    }
    let dest = URL(fileURLWithPath: destDir).appendingPathComponent(fname)
    var failure: String?
    do {
      if FileManager.default.fileExists(atPath: dest.path) {
        try FileManager.default.removeItem(at: dest)
      }
      try FileManager.default.moveItem(at: location, to: dest)
    } catch {
      failure = error.localizedDescription
    }
    tasks.removeValue(forKey: fname)
    taskOwner.removeValue(forKey: fname)
    if let failure = failure {
      setStatus(fname, ["status": "failed", "received": 0, "total": 0, "error": failure])
      postFailureNotification(name: name, error: failure)
      MiniXLiveActivity.shared.finished(filename: fname, ok: false)
    } else {
      let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? NSNumber)?.intValue ?? 0
      setStatus(fname, ["status": "completed", "received": size, "total": size])
      postCompletionNotification(name: name)
      MiniXLiveActivity.shared.finished(filename: fname, ok: true)
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask,
                  didCompleteWithError error: Error?) {
    guard let error = error,
          let filename = filename(for: task) else { return }
    if isStale(task) { return }
    tasks.removeValue(forKey: filename)
    taskOwner.removeValue(forKey: filename)
    let nsError = error as NSError
    if let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
      defaults.set(resumeData, forKey: "minix.dl.resume.\(filename)")
    }
    var current = allStatus()[filename] ?? ["status": "failed", "received": 0, "total": 0]
    current["status"] = "failed"
    current["error"] = nsError.localizedDescription
    setStatus(filename, current)
    MiniXLiveActivity.shared.finished(filename: filename, ok: false)
    let name = allMeta()[filename]?["name"] as? String ?? filename
    postFailureNotification(name: name, error: nsError.localizedDescription)
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    DispatchQueue.main.async { [weak self] in
      self?.bgCompletionHandler?()
      self?.bgCompletionHandler = nil
    }
  }

  private func filename(for task: URLSessionTask) -> String? {
    return allMeta().first(where: { $0.value["taskId"] as? Int == task.taskIdentifier })?.key
  }

  // ── Download notifications (05 completion; 27 started/failed) ──
  private func postStartedNotification(name: String) {
    let content = UNMutableNotificationContent()
    content.title = "Download started"
    content.body = "\(name) is downloading - you can leave the app."
    content.sound = .default
    content.threadIdentifier = "downloads"
    let request = UNNotificationRequest(
      identifier: "dl-start-\(name)-\(Date().timeIntervalSince1970)",
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
  }

  private func postFailureNotification(name: String, error: String) {
    let content = UNMutableNotificationContent()
    content.title = "Download failed"
    content.body = "\(name): \(error)"
    content.sound = .default
    content.threadIdentifier = "downloads"
    let request = UNNotificationRequest(
      identifier: "dl-fail-\(name)-\(Date().timeIntervalSince1970)",
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
  }

  private func postCompletionNotification(name: String) {
    let content = UNMutableNotificationContent()
    content.title = "Model ready"
    content.body = "\(name) finished downloading — tap to load."
    content.sound = .default
    content.threadIdentifier = "downloads"
    let request = UNNotificationRequest(
      identifier: "dl-\(name)-\(Date().timeIntervalSince1970)",
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
  }

  // Show the banner even when the app is in the foreground.
  func userNotificationCenter(_ center: UNUserNotificationCenter,
                              willPresent notification: UNNotification,
                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    completionHandler([.banner, .sound])
  }
}
