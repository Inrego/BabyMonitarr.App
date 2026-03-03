import Flutter
import UIKit
import AVFoundation
import AVKit
import WebRTC

// MARK: - PipFrameRenderer

@available(iOS 15.0, *)
class PipFrameRenderer: NSObject, RTCVideoRenderer {
  private let displayLayer: AVSampleBufferDisplayLayer
  private var lastFrameTimestamp: CFTimeInterval = 0
  private var staleCheckTimer: Timer?
  var onStaleStream: (() -> Void)?

  init(displayLayer: AVSampleBufferDisplayLayer) {
    self.displayLayer = displayLayer
    super.init()
  }

  func startStaleCheck() {
    staleCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
      guard let self = self else { return }
      if self.lastFrameTimestamp > 0 && CACurrentMediaTime() - self.lastFrameTimestamp > 5.0 {
        self.onStaleStream?()
      }
    }
  }

  func stopStaleCheck() {
    staleCheckTimer?.invalidate()
    staleCheckTimer = nil
  }

  func setSize(_ size: CGSize) {}

  func renderFrame(_ frame: RTCVideoFrame?) {
    guard let frame = frame else { return }
    guard let pixelBuffer = extractPixelBuffer(from: frame) else { return }
    guard let sampleBuffer = createSampleBuffer(from: pixelBuffer) else { return }

    lastFrameTimestamp = CACurrentMediaTime()

    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      if self.displayLayer.status == .failed {
        self.displayLayer.flush()
      }
      self.displayLayer.enqueue(sampleBuffer)
    }
  }

  private func extractPixelBuffer(from frame: RTCVideoFrame) -> CVPixelBuffer? {
    if let cvBuffer = frame.buffer as? RTCCVPixelBuffer {
      return cvBuffer.pixelBuffer
    }
    guard let i420 = frame.buffer.toI420() else { return nil }
    return convertI420ToPixelBuffer(i420, width: frame.width, height: frame.height)
  }

  private func convertI420ToPixelBuffer(
    _ i420: RTCI420BufferProtocol,
    width: Int32,
    height: Int32
  ) -> CVPixelBuffer? {
    var pixelBuffer: CVPixelBuffer?
    let attrs: [String: Any] = [
      kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
    ]
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      Int(width), Int(height),
      kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
      attrs as CFDictionary,
      &pixelBuffer
    )
    guard status == kCVReturnSuccess, let pb = pixelBuffer else { return nil }

    CVPixelBufferLockBaseAddress(pb, [])
    defer { CVPixelBufferUnlockBaseAddress(pb, []) }

    let yDest = CVPixelBufferGetBaseAddressOfPlane(pb, 0)!
    let yDestStride = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
    let ySrc = i420.dataY
    let ySrcStride = i420.strideY
    for row in 0..<Int(height) {
      memcpy(yDest + row * yDestStride, ySrc + row * Int(ySrcStride), Int(width))
    }

    let uvDest = CVPixelBufferGetBaseAddressOfPlane(pb, 1)!
    let uvDestStride = CVPixelBufferGetBytesPerRowOfPlane(pb, 1)
    let uSrc = i420.dataU
    let vSrc = i420.dataV
    let uStride = i420.strideU
    let vStride = i420.strideV
    let halfHeight = Int(height) / 2
    let halfWidth = Int(width) / 2
    for row in 0..<halfHeight {
      let destRow = uvDest + row * uvDestStride
      for col in 0..<halfWidth {
        destRow.advanced(by: col * 2).storeBytes(of: uSrc[row * Int(uStride) + col], as: UInt8.self)
        destRow.advanced(by: col * 2 + 1).storeBytes(of: vSrc[row * Int(vStride) + col], as: UInt8.self)
      }
    }

    return pb
  }

  private func createSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
    var formatDescription: CMFormatDescription?
    let fdStatus = CMVideoFormatDescriptionCreateForImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      formatDescriptionOut: &formatDescription
    )
    guard fdStatus == noErr, let format = formatDescription else { return nil }

    var timingInfo = CMSampleTimingInfo(
      duration: CMTime(value: 1, timescale: 30),
      presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
      decodeTimeStamp: .invalid
    )

    var sampleBuffer: CMSampleBuffer?
    let sbStatus = CMSampleBufferCreateReadyWithImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      formatDescription: format,
      sampleTiming: &timingInfo,
      sampleBufferOut: &sampleBuffer
    )
    guard sbStatus == noErr else { return nil }

    return sampleBuffer
  }
}

// MARK: - AppDelegate

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var audioInterruptionObserver: NSObjectProtocol?
  private var pipChannel: FlutterMethodChannel?
  private var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer?
  private var pipController: Any?  // AVPictureInPictureController (typed as Any for iOS <15)
  private var pipVideoTrack: RTCVideoTrack?
  private var pipFrameRenderer: Any?  // PipFrameRenderer (typed as Any for iOS <15)

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    registerAudioInterruptionObserver()
    registerPipChannel()
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  deinit {
    if let observer = audioInterruptionObserver {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  // MARK: - PIP Channel

  private func registerPipChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else { return }
    let channel = FlutterMethodChannel(name: "babymonitarr/pip", binaryMessenger: controller.binaryMessenger)
    self.pipChannel = channel

    channel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }
      switch call.method {
      case "isPipSupported":
        if #available(iOS 15.0, *) {
          result(AVPictureInPictureController.isPictureInPictureSupported())
        } else {
          result(false)
        }

      case "enterPip":
        if #available(iOS 15.0, *) {
          let success = self.startPip()
          result(success)
        } else {
          result(false)
        }

      case "exitPip":
        if #available(iOS 15.0, *) {
          self.stopPip()
        }
        result(nil)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - PIP Control

  @available(iOS 15.0, *)
  private func startPip() -> Bool {
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .moviePlayback)
      try session.setActive(true)
    } catch {
      debugPrint("PIP: Failed to configure audio session: \(error)")
      return false
    }

    guard let videoTrack = findVideoTrack() else {
      debugPrint("PIP: No active video track found")
      return false
    }

    let displayLayer = AVSampleBufferDisplayLayer()
    displayLayer.videoGravity = .resizeAspect
    self.sampleBufferDisplayLayer = displayLayer

    if let rootView = self.window?.rootViewController?.view {
      displayLayer.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
      rootView.layer.addSublayer(displayLayer)
    }

    let renderer = PipFrameRenderer(displayLayer: displayLayer)
    renderer.onStaleStream = { [weak self] in
      DispatchQueue.main.async {
        guard let self = self else { return }
        if #available(iOS 15.0, *) {
          self.stopPip()
        }
        self.pipChannel?.invokeMethod("onPipDismissed", arguments: nil)
      }
    }
    renderer.startStaleCheck()
    videoTrack.add(renderer as RTCVideoRenderer)
    self.pipFrameRenderer = renderer
    self.pipVideoTrack = videoTrack

    let contentSource = AVPictureInPictureController.ContentSource(
      sampleBufferDisplayLayer: displayLayer,
      playbackDelegate: self
    )
    let pipCtrl = AVPictureInPictureController(contentSource: contentSource)
    pipCtrl.delegate = self
    self.pipController = pipCtrl

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
      guard let self = self, let ctrl = self.pipController as? AVPictureInPictureController else { return }
      ctrl.startPictureInPicture()
    }

    return true
  }

  @available(iOS 15.0, *)
  private func stopPip() {
    if let ctrl = pipController as? AVPictureInPictureController {
      ctrl.stopPictureInPicture()
    }
    cleanupPip()
  }

  private func cleanupPip() {
    if let renderer = pipFrameRenderer as? RTCVideoRenderer, let track = pipVideoTrack {
      track.remove(renderer)
    }
    if #available(iOS 15.0, *) {
      (pipFrameRenderer as? PipFrameRenderer)?.stopStaleCheck()
    }
    pipFrameRenderer = nil
    pipVideoTrack = nil
    sampleBufferDisplayLayer?.removeFromSuperlayer()
    sampleBufferDisplayLayer = nil
    pipController = nil
  }

  // MARK: - WebRTC Video Track Discovery

  private func findVideoTrack() -> RTCVideoTrack? {
    guard let pluginClass = NSClassFromString("FlutterWebRTCPlugin") else {
      debugPrint("PIP: FlutterWebRTCPlugin class not found")
      return nil
    }

    guard let plugin = pluginClass.perform(NSSelectorFromString("sharedSingleton"))?.takeUnretainedValue() else {
      debugPrint("PIP: FlutterWebRTCPlugin singleton not available")
      return nil
    }

    guard let renders = plugin.value(forKey: "renders") as? NSDictionary else {
      debugPrint("PIP: No renders dictionary found")
      return nil
    }

    for (_, renderer) in renders {
      if let videoRenderer = renderer as? NSObject,
         let track = videoRenderer.value(forKey: "videoTrack") as? RTCVideoTrack {
        return track
      }
    }

    debugPrint("PIP: No renderer with active video track found")
    return nil
  }

  // MARK: - Audio Interruption Handling

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

// MARK: - AVPictureInPictureControllerDelegate

@available(iOS 15.0, *)
extension AppDelegate: AVPictureInPictureControllerDelegate {

  func pictureInPictureControllerDidStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    debugPrint("PIP: Did start")
    pipChannel?.invokeMethod("onPipEntered", arguments: nil)
  }

  func pictureInPictureControllerDidStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    debugPrint("PIP: Did stop")
    cleanupPip()
    pipChannel?.invokeMethod("onPipDismissed", arguments: nil)
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
  ) {
    debugPrint("PIP: Restore UI requested")
    completionHandler(true)
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    debugPrint("PIP: Failed to start: \(error)")
    cleanupPip()
    pipChannel?.invokeMethod("onPipDismissed", arguments: nil)
  }
}

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

@available(iOS 15.0, *)
extension AppDelegate: AVPictureInPictureSampleBufferPlaybackDelegate {

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    setPlaying playing: Bool
  ) {
    // Live stream — ignore play/pause
  }

  func pictureInPictureControllerTimeRangeForPlayback(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> CMTimeRange {
    return CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
  }

  func pictureInPictureControllerIsPlaybackPaused(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> Bool {
    return false
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    didTransitionToRenderSize newRenderSize: CMVideoDimensions
  ) {
    debugPrint("PIP: Render size changed to \(newRenderSize.width)x\(newRenderSize.height)")
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    skipByInterval skipInterval: CMTime,
    completion completionHandler: @escaping () -> Void
  ) {
    completionHandler()
  }
}
