import Darwin
import Flutter
import Metal
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
        var count = mach_msg_type_number_t(THREAD_BASIC_INFO_COUNT)
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
    let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
    if let free = attrs?[.systemFreeSize] as? NSNumber {
      return free.intValue
    }
    return -1
  }
}

// ── Background downloads (ticket 05) ───────────────────────────
// A background URLSession: the system daemon performs the transfer
// while MiniX is suspended or not running at all, and relaunches the
// app to deliver events. State lives in UserDefaults so it survives
// relaunches; the finished file is moved into the models directory
// synchronously in the delegate callback (the temp file is deleted
// when that callback returns), and the completion notification is
// posted natively — it never depends on the Dart side being alive.
final class MiniXDownloads: NSObject, URLSessionDownloadDelegate, UNUserNotificationCenterDelegate {
  static let shared = MiniXDownloads()

  private var session: URLSession!
  private var tasks: [String: URLSessionDownloadTask] = [:]
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
    UNUserNotificationCenter.current().delegate = self
    // Reattach to transfers the daemon kept running while we were gone.
    session.getAllTasks { [weak self] all in
      guard let self = self else { return }
      let meta = self.allMeta()
      for task in all {
        if let filename = meta.first(where: { $0.value["taskId"] as? Int == task.taskIdentifier })?.key {
          self.tasks[filename] = task as? URLSessionDownloadTask
        }
      }
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
    let task: URLSessionDownloadTask
    if let resumeData = defaults.data(forKey: "minix.dl.resume.\(filename)") {
      task = session.downloadTask(withResumeData: resumeData)
      defaults.removeObject(forKey: "minix.dl.resume.\(filename)")
    } else {
      task = session.downloadTask(with: url)
    }
    tasks[filename] = task
    setMeta(filename, ["destDir": destDir, "name": displayName, "taskId": task.taskIdentifier])
    // Belt for the relaunch path: if task identifiers ever fail to
    // match after a system relaunch, the finish delegate can still
    // place the file from the request URL + this last destination.
    defaults.set(destDir, forKey: "minix.dl.lastDestDir")
    setStatus(filename, ["status": "downloading", "received": 0, "total": 0])
    task.resume()
  }

  func cancel(filename: String) {
    tasks[filename]?.cancel()
    tasks.removeValue(forKey: filename)
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

  // ── URLSessionDownloadDelegate ───────────────────────────────
  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                  didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                  totalBytesExpectedToWrite: Int64) {
    guard let filename = filename(for: downloadTask) else { return }
    let now = Date()
    if let last = lastWrite[filename], now.timeIntervalSince(last) < 0.5 { return }
    lastWrite[filename] = now
    setStatus(filename, [
      "status": "downloading",
      "received": Int(totalBytesWritten),
      "total": Int(totalBytesExpectedToWrite),
    ])
  }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                  didFinishDownloadingTo location: URL) {
    let meta = filename(for: downloadTask).flatMap { allMeta()[$0] }
    let filename: String
    let destDir: String
    let name: String
    if let fn = filename(for: downloadTask), let m = meta,
       let dd = m["destDir"] as? String, let nm = m["name"] as? String {
      filename = fn
      destDir = dd
      name = nm
    } else if let urlName = downloadTask.originalRequest?.url?.lastPathComponent,
              urlName.hasSuffix(".gguf"),
              let dd = defaults.string(forKey: "minix.dl.lastDestDir") {
      // Relaunch fallback: identify the transfer by its request URL.
      filename = urlName
      destDir = dd
      name = urlName
    } else {
      return
    }
    let dest = URL(fileURLWithPath: destDir).appendingPathComponent(filename)
    var failure: String?
    do {
      if FileManager.default.fileExists(atPath: dest.path) {
        try FileManager.default.removeItem(at: dest)
      }
      try FileManager.default.moveItem(at: location, to: dest)
    } catch {
      failure = error.localizedDescription
    }
    tasks.removeValue(forKey: filename)
    if let failure = failure {
      setStatus(filename, ["status": "failed", "received": 0, "total": 0, "error": failure])
    } else {
      let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? NSNumber)?.intValue ?? 0
      setStatus(filename, ["status": "completed", "received": size, "total": size])
      postCompletionNotification(name: name)
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask,
                  didCompleteWithError error: Error?) {
    guard let error = error,
          let filename = filename(for: task) else { return }
    tasks.removeValue(forKey: filename)
    let nsError = error as NSError
    if let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
      defaults.set(resumeData, forKey: "minix.dl.resume.\(filename)")
    }
    var current = allStatus()[filename] ?? ["status": "failed", "received": 0, "total": 0]
    current["status"] = "failed"
    current["error"] = nsError.localizedDescription
    setStatus(filename, current)
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

  // ── Completion notification ──────────────────────────────────
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
