import Flutter
import Photos
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
    RushNativeChannel.register(with: engineBridge.applicationRegistrar.messenger())
  }
}

/// Swift twin of MainActivity.kt's "rush_demo/native" handler — the same
/// image pipeline (decode → resize → JPEG encode → save to gallery) with the
/// same per-stage timings, so the MethodChannel benchmark cards work on iOS.
enum RushNativeChannel {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "rush_demo/native", binaryMessenger: messenger)
    channel.setMethodCallHandler(handle)
  }

  private static func handle(
    _ call: FlutterMethodCall, result: @escaping FlutterResult
  ) {
    switch call.method {
    case "resizeCompressSave":
      // Full round-trip: the JPEG bytes were copied across the bridge to get
      // here. Decode + resize + encode + save natively, return stage timings.
      guard let args = call.arguments as? [String: Any],
        let bytes = args["bytes"] as? FlutterStandardTypedData,
        let width = args["width"] as? Int,
        let height = args["height"] as? Int,
        let quality = args["quality"] as? Int
      else {
        result(FlutterError(code: "BAD_ARGS", message: "missing arguments", details: nil))
        return
      }
      // Off the platform thread — mirror of Kotlin's Thread {}.
      DispatchQueue.global(qos: .userInitiated).async {
        runPipeline(
          data: bytes.data, url: nil,
          width: width, height: height, quality: quality, result: result)
      }

    case "readProcessSave":
      // Bridge receives only a file path string (~O(1) bytes, no image copy).
      guard let args = call.arguments as? [String: Any],
        let path = args["path"] as? String,
        let width = args["width"] as? Int,
        let height = args["height"] as? Int,
        let quality = args["quality"] as? Int
      else {
        result(FlutterError(code: "BAD_ARGS", message: "missing arguments", details: nil))
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        runPipeline(
          data: nil, url: URL(fileURLWithPath: path),
          width: width, height: height, quality: quality, result: result)
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// decode → resize → JPEG encode → save to Photos, timing each stage the
  /// same way the Kotlin side does.
  private static func runPipeline(
    data: Data?, url: URL?,
    width: Int, height: Int, quality: Int,
    result: @escaping FlutterResult
  ) {
    func fail(_ message: String) {
      DispatchQueue.main.async {
        result(FlutterError(code: "NATIVE_ERROR", message: message, details: nil))
      }
    }
    func elapsedMs(since start: DispatchTime) -> Int {
      Int((DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
    }

    // --- decode (forced immediately — parity with BitmapFactory.decodeByteArray) ---
    let decodeStart = DispatchTime.now()
    let decodeOptions =
      [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
    let source: CGImageSource?
    if let data = data {
      source = CGImageSourceCreateWithData(data as CFData, nil)
    } else {
      source = CGImageSourceCreateWithURL(url! as CFURL, nil)
    }
    guard let source = source,
      let decoded = CGImageSourceCreateImageAtIndex(source, 0, decodeOptions)
    else {
      fail("decode failed")
      return
    }
    let decodeMs = elapsedMs(since: decodeStart)

    // --- process: scale to target. interpolationQuality .medium is the
    // bilinear-family filter — parity with createScaledBitmap(filter=true). ---
    let processStart = DispatchTime.now()
    guard
      let context = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else {
      fail("context creation failed")
      return
    }
    context.interpolationQuality = .medium
    context.draw(decoded, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let scaled = context.makeImage() else {
      fail("resize failed")
      return
    }
    let processMs = elapsedMs(since: processStart)

    // --- encode ---
    let encodeStart = DispatchTime.now()
    guard
      let jpeg = UIImage(cgImage: scaled)
        .jpegData(compressionQuality: CGFloat(quality) / 100.0)
    else {
      fail("encode failed")
      return
    }
    let encodeMs = elapsedMs(since: encodeStart)

    // --- save to the photo library (mirror of the MediaStore insert) ---
    let saveStart = DispatchTime.now()
    do {
      try PHPhotoLibrary.shared().performChangesAndWait {
        let request = PHAssetCreationRequest.forAsset()
        request.addResource(with: .photo, data: jpeg, options: nil)
      }
    } catch {
      fail("save failed: \(error.localizedDescription)")
      return
    }
    let saveMs = elapsedMs(since: saveStart)

    let payload: [String: Any] = [
      "decodeMs": decodeMs,
      "processMs": processMs,
      "encodeMs": encodeMs,
      "saveMs": saveMs,
      "outputBytes": jpeg.count,
    ]
    DispatchQueue.main.async { result(payload) }
  }
}
