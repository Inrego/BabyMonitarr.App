import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var audioInterruptionObserver: NSObjectProtocol?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    registerAudioInterruptionObserver()
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  deinit {
    if let observer = audioInterruptionObserver {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  private func registerAudioInterruptionObserver() {
    let session = AVAudioSession.sharedInstance()
    audioInterruptionObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification,
      object: session,
      queue: .main
    ) { [weak self] notification in
      self?.handleAudioInterruption(notification)
    }
  }

  private func handleAudioInterruption(_ notification: Notification) {
    guard
      let userInfo = notification.userInfo,
      let rawType = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
      let type = AVAudioSession.InterruptionType(rawValue: rawType)
    else {
      return
    }

    guard type == .ended else {
      return
    }

    let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
    guard options.contains(.shouldResume) else {
      return
    }

    do {
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      debugPrint("AppDelegate: failed to reactivate audio session: \(error)")
    }
  }
}
