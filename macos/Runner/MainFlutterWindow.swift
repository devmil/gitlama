import Cocoa
import FlutterMacOS
import QuartzCore
import desktop_multi_window

class MainFlutterWindow: NSWindow {
  private var launchScreen: LaunchScreenView?
  private var launchScreenChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // Flutter's content starts black otherwise.
    backgroundColor = .windowBackgroundColor
    flutterViewController.backgroundColor = .windowBackgroundColor
    let windowFrame = self.frame
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)
    if #available(macOS 11.0, *) {
      self.titlebarSeparatorStyle = .none
    }
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Native menus come from the meridian_native_menus plugin, which the
    // generated registrant installs in every window.
    RegisterGeneratedPlugins(registry: flutterViewController)
    ApplicationOpenBridge.shared.register(
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    AppUpdateBridge.shared.register(
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    installLaunchScreen(on: flutterViewController)
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
    }

    super.awakeFromNib()
  }

  /// Covers Flutter with the app icon until Dart reports its first frame.
  /// That frame (the startup screen) shows the same mark in the same place,
  /// so the cover fades straight into it.
  private func installLaunchScreen(on flutterViewController: FlutterViewController) {
    let cover = LaunchScreenView()
    cover.translatesAutoresizingMaskIntoConstraints = false
    flutterViewController.view.addSubview(cover)
    NSLayoutConstraint.activate([
      cover.leadingAnchor.constraint(equalTo: flutterViewController.view.leadingAnchor),
      cover.trailingAnchor.constraint(equalTo: flutterViewController.view.trailingAnchor),
      cover.topAnchor.constraint(equalTo: flutterViewController.view.topAnchor),
      cover.bottomAnchor.constraint(equalTo: flutterViewController.view.bottomAnchor),
    ])
    launchScreen = cover
    let channel = FlutterMethodChannel(
      name: "gitlama/native_launch_screen",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "ready" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.dismissLaunchScreen()
      result(nil)
    }
    launchScreenChannel = channel
  }

  private func dismissLaunchScreen() {
    guard let cover = launchScreen else { return }
    launchScreen = nil
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.2
      context.timingFunction = CAMediaTimingFunction(name: .easeIn)
      cover.animator().alphaValue = 0
    } completionHandler: { [weak self] in
      cover.removeFromSuperview()
      self?.launchScreenChannel?.setMethodCallHandler(nil)
      self?.launchScreenChannel = nil
    }
  }
}

/// The app icon centred on the window background, 128 pt like Flutter's
/// `GitLamaLayout.launchMarkSize`.
private final class LaunchScreenView: NSView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    configure()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configure()
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.windowBackgroundColor.setFill()
    dirtyRect.fill()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }

  private func configure() {
    let logo = NSImageView(image: NSApplication.shared.applicationIconImage)
    logo.imageScaling = .scaleProportionallyUpOrDown
    logo.translatesAutoresizingMaskIntoConstraints = false
    addSubview(logo)
    NSLayoutConstraint.activate([
      logo.centerXAnchor.constraint(equalTo: centerXAnchor),
      logo.centerYAnchor.constraint(equalTo: centerYAnchor),
      logo.widthAnchor.constraint(equalToConstant: 128),
      logo.heightAnchor.constraint(equalToConstant: 128),
    ])
  }
}
