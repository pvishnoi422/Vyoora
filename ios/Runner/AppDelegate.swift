import Flutter
import UIKit
import Photos
import ImageIO

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var exportChannel: FlutterMethodChannel?
  private var sharing = false
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "VyooraExports") {
      let channel = FlutterMethodChannel(name: "vyoora/exports", binaryMessenger: registrar.messenger())
      exportChannel = channel
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else { return }
        self.handleExport(call, result: result)
      }
    }
  }

  private func exportedImage(_ value: Any?) -> UIImage? {
    guard let typed = value as? FlutterStandardTypedData, typed.data.count <= 7 * 1024 * 1024,
      let source = CGImageSourceCreateWithData(typed.data as CFData, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width > 0, height > 0, Double(width) * Double(height) <= 20_000_000,
      let image = UIImage(data: typed.data) else { return nil }
    let size = CGSize(width: width, height: height)
    let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: size))
      let fontSize = max(12, size.width * 0.021)
      let padding = max(8, size.width * 0.015)
      let label = "VYOORA · AI PREVIEW" as NSString
      let attributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: fontSize, weight: .medium),
        .foregroundColor: UIColor.white.withAlphaComponent(0.9)
      ]
      let textSize = label.size(withAttributes: attributes)
      let rect = CGRect(x: size.width - textSize.width - padding * 2,
        y: size.height - textSize.height - padding * 2,
        width: textSize.width + padding, height: textSize.height + padding)
      UIColor.black.withAlphaComponent(0.35).setFill()
      UIBezierPath(roundedRect: rect, cornerRadius: padding / 2).fill()
      label.draw(at: CGPoint(x: rect.minX + padding / 2, y: rect.minY + padding / 2), withAttributes: attributes)
    }
  }

  private func presenter() -> UIViewController? {
    var controller = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }.first(where: { $0.isKeyWindow })?.rootViewController
    while let presented = controller?.presentedViewController { controller = presented }
    return controller
  }

  private func handleExport(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    #if DEBUG
    if call.method == "testWatermark" {
      result(exportedImage(call.arguments)?.pngData().map { FlutterStandardTypedData(bytes: $0) }); return
    }
    if call.method == "testSharePresented" { result(presenter() is UIActivityViewController); return }
    if call.method == "testDismissShare" {
      let sheet = presenter() as? UIActivityViewController
      sheet?.dismiss(animated: false) { sheet?.completionWithItemsHandler?(nil, false, nil, nil) }
      result(nil); return
    }
    #endif
    guard ["save", "share"].contains(call.method) else { result(FlutterMethodNotImplemented); return }
    guard let image = exportedImage(call.arguments) else {
      result(FlutterError(code: "invalid_image", message: "This image cannot be exported.", details: nil)); return
    }
    if call.method == "save" {
      guard #available(iOS 14, *) else {
        result(FlutterError(code: "ios_version", message: "Saving requires iOS 14 or later.", details: nil)); return
      }
      PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
        guard status == .authorized || status == .limited else {
          DispatchQueue.main.async { result(FlutterError(code: "permission_denied", message: "Allow adding photos in Settings.", details: nil)) }; return
        }
        var identifier: String?
        PHPhotoLibrary.shared().performChanges({
          identifier = PHAssetChangeRequest.creationRequestForAsset(from: image).placeholderForCreatedAsset?.localIdentifier
        }) { saved, _ in
          DispatchQueue.main.async {
            if saved, let identifier = identifier { result(identifier) }
            else { result(FlutterError(code: "save_failed", message: "Photos could not save this image.", details: nil)) }
          }
        }
      }
      return
    }
    guard !sharing, let controller = presenter(), !(controller is UIActivityViewController) else {
      result(FlutterError(code: "busy", message: "Finish the current share first.", details: nil)); return
    }
    // An image item lets iOS offer installed compatible apps. No private URL or
    // photo is sent to a social service until the person chooses that service.
    sharing = true
    let sheet = UIActivityViewController(activityItems: [image], applicationActivities: nil)
    sheet.popoverPresentationController?.sourceView = controller.view
    sheet.popoverPresentationController?.sourceRect = CGRect(x: controller.view.bounds.midX,
      y: controller.view.bounds.midY, width: 1, height: 1)
    sheet.completionWithItemsHandler = { [weak self] _, completed, _, error in
      self?.sharing = false
      if error != nil { result(FlutterError(code: "share_failed", message: "Sharing failed.", details: nil)) }
      else { result(completed) }
    }
    controller.present(sheet, animated: true)
  }
}
