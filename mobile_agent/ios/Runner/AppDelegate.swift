import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let htmlRenderRunner = HtmlRenderRunner()
  private var pendingInitialDeepLink: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let url = launchOptions?[.url] as? URL {
      captureDeepLink(url)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    captureDeepLink(url)
    return super.application(app, open: url, options: options)
  }

  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    if let url = userActivity.webpageURL {
      captureDeepLink(url)
    }
    return super.application(
      application,
      continue: userActivity,
      restorationHandler: restorationHandler
    )
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    let htmlChannel = FlutterMethodChannel(
      name: "mobilecode/html_renderer",
      binaryMessenger: messenger
    )
    htmlChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "renderer_unavailable", message: "AppDelegate is unavailable", details: nil))
        return
      }
      guard call.method == "renderPng" || call.method == "renderPdf" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let arguments = call.arguments as? [String: Any] else {
        result(FlutterError(code: "invalid_request", message: "HTML renderer requires a map", details: nil))
        return
      }
      if call.method == "renderPdf" {
        self.htmlRenderRunner.renderPdf(arguments: arguments, result: result)
      } else {
        self.htmlRenderRunner.renderPng(arguments: arguments, result: result)
      }
    }

    let systemToolsChannel = FlutterMethodChannel(
      name: "mobilecode/system_tools",
      binaryMessenger: messenger
    )
    systemToolsChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "system_tools_unavailable", message: "AppDelegate is unavailable", details: nil))
        return
      }
      self.handleSystemToolsCall(call, result: result)
    }

    let platformChannel = FlutterMethodChannel(
      name: "mobile_coding/platform",
      binaryMessenger: messenger
    )
    platformChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "getBuildTags":
        result("")
      case "getInstallerPackage":
        result(nil)
      case "isAppStoreBuild":
        result(Bundle.main.appStoreReceiptURL?.lastPathComponent == "receipt")
      case "verifySignature":
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func captureDeepLink(_ url: URL) {
    guard url.scheme?.lowercased() == "mobilecode" else { return }
    pendingInitialDeepLink = url.absoluteString
  }

  func handleSystemToolsCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "consumePendingSharedFile":
      // iOS currently has no share extension. Returning nil is an intentional,
      // supported empty state and prevents a MissingPluginException at launch.
      result(nil)
    case "consumeInitialDeepLink":
      let value = pendingInitialDeepLink
      pendingInitialDeepLink = nil
      result(value)
    case "getDeviceTelemetry":
      result(deviceTelemetry())
    case "isPackageInstalled", "launchPackage", "startHelperService", "stopHelperService":
      result(false)
    case "rootProbe":
      result([
        "available": false,
        "detail": "Root helpers are not available on iOS.",
      ])
    case "helperServiceStatus", "linuxSandboxStatus":
      result([
        "available": false,
        "ready": false,
        "status": "unsupported_platform",
        "platform": "ios",
      ])
    case "linuxSandboxSetup", "linuxSandboxReset", "linuxSandboxRunTypedTask":
      result(blockedResult("unsupported_platform"))
    case "getPhoneUseAccessibilityStatus":
      result(phoneUseStatus())
    case "openPhoneUseAccessibilitySettings", "openBatteryOptimizationSettings":
      result(false)
    case "openAppSettings":
      openAppSettings(result: result)
    case "runPhoneUseDryProbe", "markPhoneUseRecoveryRequested",
         "capturePhoneUseScreenshot", "performPhoneUseAction":
      result(blockedResult("ios_requires_external_xctest_provider"))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func openAppSettings(result: @escaping FlutterResult) {
    guard let url = URL(string: UIApplication.openSettingsURLString) else {
      result(false)
      return
    }
    UIApplication.shared.open(url, options: [:]) { opened in
      result(opened)
    }
  }

  private func phoneUseStatus() -> [String: Any] {
    [
      "platform": "ios",
      "supported": false,
      "serviceId": "",
      "accessibilityEnabled": false,
      "serviceConnected": false,
      "lifecycleState": "unsupported",
      "canObserveActiveWindow": false,
      "canPerformGestures": false,
      "canSetText": false,
      "canCaptureScreenshot": false,
      "batteryOptimizationIgnored": false,
      "backgroundRestricted": false,
      "supportedActions": [],
      "blockedReason": "ios_requires_external_xctest_provider",
      "recoveryActions": ["Use the Mac-hosted XCTest or agent-device provider."],
      "eventCount": 0,
      "countsAsExperiment": false,
      "countsAsStrategyAblationResult": false,
      "rawTextIncluded": false,
      "redactionApplied": true,
      "fallback": false,
    ]
  }

  private func blockedResult(_ failureKind: String) -> [String: Any] {
    [
      "status": "blocked",
      "failureKind": failureKind,
      "platform": "ios",
      "countsAsExperiment": false,
      "countsAsStrategyAblationResult": false,
      "rawTextIncluded": false,
      "redactionApplied": true,
    ]
  }

  private func deviceTelemetry() -> [String: Any] {
    let device = UIDevice.current
    device.isBatteryMonitoringEnabled = true
    let batteryLevel = device.batteryLevel < 0
      ? -1
      : Int((device.batteryLevel * 100).rounded())
    let batteryCharging = device.batteryState == .charging || device.batteryState == .full
    let fileSystem = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
    let totalBytes = (fileSystem?[.systemSize] as? NSNumber)?.int64Value ?? 0
    let freeBytes = (fileSystem?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
    return [
      "platform": "ios",
      "manufacturer": "Apple",
      "model": device.model,
      "androidVersion": device.systemVersion,
      "sdkInt": 0,
      "abis": [],
      "cpuCores": ProcessInfo.processInfo.processorCount,
      "cpuUsagePercent": 0.0,
      "totalMemoryMb": Int64(ProcessInfo.processInfo.physicalMemory / 1_048_576),
      "availableMemoryMb": 0,
      "lowMemory": false,
      "appRssMb": 0,
      "appHeapMb": 0,
      "storageTotalMb": totalBytes / 1_048_576,
      "storageFreeMb": freeBytes / 1_048_576,
      "batteryLevel": batteryLevel,
      "batteryCharging": batteryCharging,
      "batteryTemperatureC": 0.0,
      "thermalStatus": ProcessInfo.processInfo.thermalState.rawValue,
      "timestamp": Int(Date().timeIntervalSince1970 * 1000),
      "fallback": false,
    ]
  }
}
