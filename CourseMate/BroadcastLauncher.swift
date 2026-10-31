//
//  BroadcastLauncher.swift
//
//  Starting the broadcast from inside the app is a nicer path than Control
//  Centre: it hands the extension the current session with no manual copying.
//  RPBroadcastActivityViewController is a UIKit controller, so this drives it
//  from the key window and mirrors its state into @Published values.
//
import ReplayKit
import UIKit

final class BroadcastLauncher: NSObject, ObservableObject {
    @Published private(set) var isBroadcasting = false
    @Published private(set) var message: String?

    private var controller: RPBroadcastController?
    private weak var presenter: UIViewController?

    func start() {
        guard let host = Self.topViewController() else {
            message = "No window to present from."
            return
        }
        presenter = host
        message = nil

        RPBroadcastActivityViewController.load { [weak self] activity, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let activity else {
                    self.message = error?.localizedDescription
                        ?? "No broadcast extension available. Build and install the extension target first."
                    return
                }
                activity.delegate = self
                activity.popoverPresentationController?.sourceView = host.view
                host.present(activity, animated: true)
            }
        }
    }

    func stop() {
        controller?.finishBroadcast { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isBroadcasting = false
                self.controller = nil
                if let error { self.message = error.localizedDescription }
            }
        }
    }

    /// The system broadcast sheet must be presented from the frontmost
    /// controller, not from the window root, or it is swallowed on iPad.
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

extension BroadcastLauncher: RPBroadcastActivityViewControllerDelegate {
    func broadcastActivityViewController(
        _ broadcastActivityViewController: RPBroadcastActivityViewController,
        didFinishWith broadcastController: RPBroadcastController?,
        error: Error?
    ) {
        let host = presenter
        DispatchQueue.main.async {
            broadcastActivityViewController.dismiss(animated: true) {
                guard let broadcastController else {
                    self.message = error?.localizedDescription ?? "Broadcast was not started."
                    return
                }
                broadcastController.startBroadcast { startError in
                    DispatchQueue.main.async {
                        if let startError {
                            self.message = startError.localizedDescription
                            return
                        }
                        self.controller = broadcastController
                        self.isBroadcasting = true
                    }
                }
            }
            _ = host
        }
    }
}
