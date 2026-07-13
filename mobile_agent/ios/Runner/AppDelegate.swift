import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let htmlRenderRunner = HtmlRenderRunner()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "mobilecode/html_renderer",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
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
  }
}
