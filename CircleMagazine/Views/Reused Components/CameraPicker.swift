//
//  CameraPicker.swift
//  CircleMagazine
//
//  The camera, for reacting to a post with a photo you take rather than one you
//  had lying around.
//
//  A UIImagePickerController wrapper rather than an AVFoundation capture session:
//  the system controller brings the shutter, the retake/use review step, flash,
//  the front/back flip and the permission prompt, which is several hundred lines
//  of AVFoundation to reach the same place. When the chrome-less Snapchat-style
//  capture surface matters more than the shipping date, that's the upgrade.
//
//  It also reports availability, which is what lets the whole flow be exercised
//  in the simulator: there's no camera there, so `isAvailable` is false and the
//  caller takes the photo-library path — a branch that has to work on a real
//  device anyway (denied permission, an iPad without a rear camera).
//

import SwiftUI
import AVFoundation
import UIKit

struct CameraPicker: UIViewControllerRepresentable {
    /// Handed the captured image. The caller owns encoding and uploading — a
    /// UIImage is a UIKit type and keeping it out of the ViewModels is what lets
    /// them be tested without a camera.
    let onCapture: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    /// False on every simulator, and on hardware without a usable camera.
    static var isAvailable: Bool {
        #if targetEnvironment(simulator)
        // The iOS 26 simulator *claims* a camera and even shows the capture UI,
        // but its shutter never hands back an image — so believing it means the
        // reaction flow can't be exercised without a device. Hardcoded false
        // instead, which routes the sim down the library fallback: the same
        // branch a device takes when camera access is denied.
        false
        #else
        UIImagePickerController.isSourceTypeAvailable(.camera)
        #endif
    }

    /// Whether the camera can be opened *right now*. Presenting the picker after
    /// the viewer has denied access shows a black rectangle with no explanation,
    /// so the caller checks this first and falls back to the library instead.
    static var isPermitted: Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted: false
        default: true               // .authorized, or .notDetermined → the picker asks
        }
    }

    /// Camera if there is one and we're allowed it; otherwise the library.
    static var canUseCamera: Bool { isAvailable && isPermitted }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, dismiss: { dismiss() })
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (UIImage) -> Void
        private let dismiss: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, dismiss: @escaping () -> Void) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { onCapture(image) }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

extension UIImage {
    /// JPEG bytes, downscaled first. A modern camera frame is ~12MP and several
    /// megabytes; a reaction is a thumbnail-sized face on a card, and there's one
    /// per member per post, so uploading the full frame would multiply fast.
    ///
    /// ponytail: compose still uploads full-resolution photos — worth pointing at
    /// this too when someone next touches it.
    func reactionJPEG(maxEdge: CGFloat = 1080, quality: CGFloat = 0.8) -> Data? {
        let longest = max(size.width, size.height)
        guard longest > maxEdge else { return jpegData(compressionQuality: quality) }

        let scale = maxEdge / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1            // target is already in pixels
        return UIGraphicsImageRenderer(size: target, format: format)
            .image { _ in draw(in: CGRect(origin: .zero, size: target)) }
            .jpegData(compressionQuality: quality)
    }
}
