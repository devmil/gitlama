import Cocoa
import FlutterMacOS
import Sparkle

/// Gives the process the PATH of the user's login shell before a thread or a
/// window exists. An application started from Finder or the Dock inherits a
/// PATH without the shell's additions, so Git would not find helpers such as
/// git-lfs. The native core restarts the process once when PATH differs and
/// returns otherwise; without the core the application starts unchanged.
private func prepareDesktopEnvironment() {
  guard let frameworks = Bundle.main.privateFrameworksPath,
        let core = dlopen(
          frameworks + "/gitlama_core.framework/gitlama_core", RTLD_NOW),
        let prepare = dlsym(core, "gitlama_prepare_desktop_environment") else {
    return
  }
  typealias Prepare = @convention(c) () -> Void
  unsafeBitCast(prepare, to: Prepare.self)()
}

@main
class AppDelegate: FlutterAppDelegate {
  static func main() {
    prepareDesktopEnvironment()
    _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    let local = urls.filter { $0.isFileURL }
    if !local.isEmpty {
      _ = ApplicationOpenBridge.shared.enqueue(local.map { $0.path })
    }
    let other = urls.filter { !$0.isFileURL }
    if !other.isEmpty {
      super.application(application, open: other)
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

/// Runs Sparkle for the Dart update service over `gitlama/app_update`.
///
/// Dart supplies the feed and the release channel. The updater starts on the
/// first `configure`, so a process that never configures it (a debug run or a
/// qualification launch) leaves Sparkle and its user defaults untouched.
final class AppUpdateBridge: NSObject, SPUUpdaterDelegate {
  static let shared = AppUpdateBridge()

  private var channel: FlutterMethodChannel?
  private var userDriver: SPUStandardUserDriver?
  private var updater: SPUUpdater?
  private var feedURL: String?
  private var allowedChannels = Set<String>()

  func register(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "gitlama/app_update",
      binaryMessenger: binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    self.channel = channel
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "configure":
      guard let arguments = call.arguments as? [String: Any],
            let feed = arguments["feedUrl"] as? String,
            let url = URL(string: feed), url.scheme == "https", url.host != nil,
            let releaseChannel = arguments["releaseChannel"] as? String,
            releaseChannel == "stable" || releaseChannel == "beta",
            let interval = arguments["checkIntervalSeconds"] as? Int,
            interval >= 3600 else {
        result(FlutterError(code: "app_update_invalid_request", message: nil, details: nil))
        return
      }
      feedURL = feed
      allowedChannels = releaseChannel == "beta" ? ["beta"] : []
      guard let updater = startedUpdater() else {
        result(FlutterError(code: "app_update_unavailable", message: nil, details: nil))
        return
      }
      updater.updateCheckInterval = TimeInterval(interval)
      updater.resetUpdateCycle()
      result(nil)
    case "checkForUpdates":
      guard let updater else {
        result(FlutterError(code: "app_update_unavailable", message: nil, details: nil))
        return
      }
      updater.checkForUpdates()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func startedUpdater() -> SPUUpdater? {
    if let updater { return updater }
    let bundle = Bundle.main
    let driver = SPUStandardUserDriver(hostBundle: bundle, delegate: nil)
    let candidate = SPUUpdater(
      hostBundle: bundle,
      applicationBundle: bundle,
      userDriver: driver,
      delegate: self)
    // The feed comes from the delegate; drop any value a user default holds.
    candidate.clearFeedURLFromUserDefaults()
    do {
      try candidate.start()
    } catch {
      return nil
    }
    userDriver = driver
    updater = candidate
    return candidate
  }

  func allowedChannels(for updater: SPUUpdater) -> Set<String> {
    allowedChannels
  }

  func feedURLString(for updater: SPUUpdater) -> String? {
    feedURL
  }
}

/// Launch Services can deliver paths before Dart or the workspace is ready.
/// Keep them in the main engine's queue until the attached service takes them.
final class ApplicationOpenBridge {
  static let shared = ApplicationOpenBridge()
  private var pending: [String] = []
  private var channel: FlutterMethodChannel?

  func enqueue(_ paths: [String]) -> Bool {
    guard !paths.isEmpty, pending.count + paths.count <= 64,
          paths.allSatisfy({ !$0.isEmpty && !$0.contains("\0") && $0.utf8.count <= 32768 }) else {
      return false
    }
    pending.append(contentsOf: paths)
    return true
  }

  func takePaths() -> [String] {
    let batch = Array(pending.prefix(8))
    pending.removeFirst(batch.count)
    return batch
  }

  func register(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "gitlama/application_open", binaryMessenger: binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "takePaths" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(self?.takePaths() ?? [])
    }
    self.channel = channel
  }
}
