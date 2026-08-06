import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    capture(connectionOptions.urlContexts.map(\.url))
    if let url = connectionOptions.userActivities.first?.webpageURL {
      capture([url])
    }
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    capture(URLContexts.map(\.url))
    super.scene(scene, openURLContexts: URLContexts)
  }

  override func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    if let url = userActivity.webpageURL {
      capture([url])
    }
    super.scene(scene, continue: userActivity)
  }

  private func capture(_ urls: [URL]) {
    guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
    for url in urls {
      appDelegate.captureDeepLink(url)
    }
  }
}
