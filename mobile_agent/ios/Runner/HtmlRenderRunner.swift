import Flutter
import UIKit
import WebKit

/// Captures a viewport bitmap from an iOS WKWebView without changing the
/// visible preview WebView owned by Flutter.
final class HtmlRenderRunner: NSObject, WKNavigationDelegate {
  private enum Format {
    case png
    case pdf
  }

  private final class Session {
    let result: FlutterResult
    let width: Int
    let height: Int
    let scale: CGFloat
    let format: Format
    var timeout: DispatchWorkItem?

    init(result: @escaping FlutterResult, width: Int, height: Int, scale: CGFloat, format: Format) {
      self.result = result
      self.width = width
      self.height = height
      self.scale = scale
      self.format = format
    }
  }

  private var sessions: [ObjectIdentifier: Session] = [:]

  func renderPng(arguments: [String: Any], result: @escaping FlutterResult) {
    render(arguments: arguments, result: result, format: .png)
  }

  func renderPdf(arguments: [String: Any], result: @escaping FlutterResult) {
    render(arguments: arguments, result: result, format: .pdf)
  }

  private func render(arguments: [String: Any], result: @escaping FlutterResult, format: Format) {
    guard let rawURL = arguments["url"] as? String,
          let url = URL(string: rawURL),
          !rawURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      let methodName = format == .png ? "renderPng" : "renderPdf"
      result(FlutterError(code: "invalid_request", message: "\(methodName) requires a valid url", details: nil))
      return
    }

    let width = number(arguments["width"], fallback: 390).clamped(to: 240...4096)
    let height = number(arguments["height"], fallback: 844).clamped(to: 320...4096)
    let scale = CGFloat((arguments["deviceScaleFactor"] as? NSNumber)?.doubleValue ?? 1.0)
      .clamped(to: 0.5...4.0)
    let timeoutMs = number(arguments["timeoutMs"], fallback: 15000).clamped(to: 1000...60000)

    DispatchQueue.main.async { [weak self] in
      guard let self, let rootView = self.rootView() else {
        result(FlutterError(code: "renderer_unavailable", message: "No host view is available", details: nil))
        return
      }

      let configuration = WKWebViewConfiguration()
      configuration.preferences.javaScriptEnabled = true
      let webView = WKWebView(
        frame: CGRect(x: -CGFloat(width), y: 0, width: CGFloat(width), height: CGFloat(height)),
        configuration: configuration
      )
      webView.navigationDelegate = self
      webView.isOpaque = false
      webView.alpha = 0.01
      webView.isUserInteractionEnabled = false
      webView.scrollView.isScrollEnabled = false
      rootView.addSubview(webView)

      let key = ObjectIdentifier(webView)
      let session = Session(result: result, width: width, height: height, scale: scale, format: format)
      self.sessions[key] = session
      session.timeout = DispatchWorkItem { [weak self, weak webView] in
        guard let self, let webView else { return }
        self.finish(webView: webView, error: FlutterError(
          code: "timeout",
          message: "HTML renderer timed out after \(timeoutMs)ms",
          details: nil
        ))
      }
      if let timeout = session.timeout {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(timeoutMs), execute: timeout)
      }
      webView.load(URLRequest(url: url))
    }
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    let javascript = "(function(){var m=document.querySelector('meta[name=viewport]');" +
      "if(!m){m=document.createElement('meta');m.name='viewport';document.head.appendChild(m);}" +
      "m.content='width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no';})();"
    webView.evaluateJavaScript(javascript) { [weak self, weak webView] _, _ in
      guard let self, let webView else { return }
      DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) {
        self.capture(webView: webView)
      }
    }
  }

  func webView(
    _ webView: WKWebView,
    didFail navigation: WKNavigation!,
    withError error: Error
  ) {
    finish(webView: webView, error: FlutterError(
      code: "load_failed",
      message: error.localizedDescription,
      details: nil
    ))
  }

  func webView(
    _ webView: WKWebView,
    didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    finish(webView: webView, error: FlutterError(
      code: "load_failed",
      message: error.localizedDescription,
      details: nil
    ))
  }

  private func capture(webView: WKWebView) {
    guard let session = sessions[ObjectIdentifier(webView)] else { return }
    if session.format == .pdf {
      capturePdf(webView: webView, session: session)
      return
    }
    let configuration = WKSnapshotConfiguration()
    configuration.rect = CGRect(
      x: 0,
      y: 0,
      width: CGFloat(session.width),
      height: CGFloat(session.height)
    )
    configuration.afterScreenUpdates = true
    configuration.snapshotWidth = NSNumber(value: CGFloat(session.width) * session.scale)

    webView.takeSnapshot(with: configuration) { [weak self, weak webView] image, error in
      guard let self, let webView else { return }
      if let error {
        self.finish(webView: webView, error: FlutterError(
          code: "capture_failed",
          message: error.localizedDescription,
          details: nil
        ))
        return
      }
      guard let image, let data = image.pngData() else {
        self.finish(webView: webView, error: FlutterError(
          code: "capture_failed",
          message: "WKWebView returned no PNG data",
          details: nil
        ))
        return
      }
      do {
        let directory = try self.renderDirectory()
        let output = directory.appendingPathComponent("preview_\(Int(Date().timeIntervalSince1970 * 1000)).png")
        try data.write(to: output, options: .atomic)
        self.finish(webView: webView, value: [
          "path": output.path,
          "mimeType": "image/png",
          "width": Int(CGFloat(session.width) * session.scale),
          "height": Int(CGFloat(session.height) * session.scale),
          "backend": "ios_wkwebview_snapshot",
          "metadata": ["deviceScaleFactor": session.scale],
        ])
      } catch {
        self.finish(webView: webView, error: FlutterError(
          code: "capture_failed",
          message: error.localizedDescription,
          details: nil
        ))
      }
    }
  }

  private func capturePdf(webView: WKWebView, session: Session) {
    guard #available(iOS 14.0, *) else {
      finish(webView: webView, error: FlutterError(
        code: "unsupported",
        message: "WKWebView PDF export requires iOS 14 or newer",
        details: nil
      ))
      return
    }
    let configuration = WKPDFConfiguration()
    configuration.rect = CGRect(
      x: 0,
      y: 0,
      width: CGFloat(session.width),
      height: CGFloat(session.height)
    )
    webView.createPDF(configuration: configuration) { [weak self, weak webView] result in
      guard let self, let webView else { return }
      let data: Data
      switch result {
      case .success(let pdfData):
        data = pdfData
      case .failure(let error):
        self.finish(webView: webView, error: FlutterError(
          code: "capture_failed",
          message: error.localizedDescription,
          details: nil
        ))
        return
      }
      guard !data.isEmpty else {
        self.finish(webView: webView, error: FlutterError(
          code: "capture_failed",
          message: "WKWebView returned no PDF data",
          details: nil
        ))
        return
      }
      do {
        let directory = try self.renderDirectory()
        let output = directory.appendingPathComponent("preview_\(Int(Date().timeIntervalSince1970 * 1000)).pdf")
        try data.write(to: output, options: .atomic)
        self.finish(webView: webView, value: [
          "path": output.path,
          "mimeType": "application/pdf",
          "width": session.width,
          "height": session.height,
          "backend": "ios_wkwebview_create_pdf",
          "metadata": ["deviceScaleFactor": session.scale],
        ])
      } catch {
        self.finish(webView: webView, error: FlutterError(
          code: "capture_failed",
          message: error.localizedDescription,
          details: nil
        ))
      }
    }
  }

  private func finish(
    webView: WKWebView,
    value: Any? = nil,
    error: FlutterError? = nil
  ) {
    let key = ObjectIdentifier(webView)
    guard let session = sessions.removeValue(forKey: key) else { return }
    session.timeout?.cancel()
    webView.stopLoading()
    webView.navigationDelegate = nil
    webView.removeFromSuperview()
    if let error {
      session.result(error)
    } else {
      session.result(value)
    }
  }

  private func rootView() -> UIView? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    return scenes
      .flatMap(\.windows)
      .first(where: { $0.isKeyWindow })?
      .rootViewController?
      .view
  }

  private func renderDirectory() throws -> URL {
    let caches = try FileManager.default.url(
      for: .cachesDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let directory = caches.appendingPathComponent("mobilecode-render", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private func number(_ value: Any?, fallback: Int) -> Int {
    (value as? NSNumber)?.intValue ?? fallback
  }
}

private extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
