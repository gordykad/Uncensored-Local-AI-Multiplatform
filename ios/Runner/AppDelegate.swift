import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Diagnostics channel (MiniX ticket 01): exposes
    // os_proc_available_memory() — the figure iOS jetsam decisions are
    // made against — to the Dart MemoryProbe.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MiniXDiagnostics") {
      let channel = FlutterMethodChannel(
        name: "minix/diagnostics",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { call, result in
        if call.method == "availableMemoryBytes" {
          result(os_proc_available_memory())
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
