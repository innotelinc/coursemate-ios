//
//  BroadcastLauncher.swift
//
//  ReplayKit has two unrelated lists and picking the wrong one is invisible in
//  the code but loud on the phone: RPBroadcastActivityViewController lists
//  broadcast *activities* — the Twitch-and-Zoom kind — and answers an app that
//  ships an upload extension with "This requires live streaming apps", because
//  from its point of view nothing is installed.
//
//  CourseMate ships an upload extension (`us.innotel.coursemate.broadcast`), and
//  the only view iOS lets start one is RPSystemBroadcastPickerView. So that is
//  what this presents, with `preferredExtension` naming our extension so the
//  sheet opens on CourseMate instead of asking the user to find it.
//
//  There is no delegate and no controller here on purpose: with the system
//  picker, iOS owns the broadcast. The app learns what is actually happening
//  from the status file the extension writes (`ControlChannel.readStatus`),
//  which is a stronger signal than "we asked for it".
//
import ReplayKit
import SwiftUI
import UIKit

final class BroadcastLauncher: NSObject, ObservableObject {
    /// Only ever a hint to the user. Whether a broadcast is really running is
    /// read back from the extension, never assumed from a tap.
    @Published private(set) var message: String?

    /// The extension this app ships, named explicitly so the sheet preselects it.
    static let extensionID = "us.innotel.coursemate.broadcast"

    /// Weak: the picker is owned by the view hierarchy. `attach` deliberately
    /// publishes nothing, because it is called from `makeUIView` and mutating
    /// published state mid-update is undefined behaviour in SwiftUI.
    private weak var picker: RPSystemBroadcastPickerView?

    func attach(_ picker: RPSystemBroadcastPickerView?) {
        self.picker = picker
    }

    /// The labelled button drives the picker's own control. That is not a trick:
    /// RPSystemBroadcastPickerView is the only view allowed to begin an upload
    /// extension broadcast, and its internal button is the only thing that
    /// responds, so the label forwards to it rather than duplicating iOS.
    func start() {
        guard let picker else {
            message = "The broadcast control has not loaded yet. Tap the round button above, or reopen this screen."
            return
        }
        guard let button = Self.control(in: picker) else {
            message = "Tap the round broadcast button above — that is the control iOS provides for this."
            return
        }
        message = nil
        button.sendActions(for: .allTouchUp)
    }

    /// The picker renders its button somewhere inside itself; the nesting has
    /// changed between iOS releases, so walk the tree instead of assuming depth.
    private static func control(in view: UIView) -> UIControl? {
        for subview in view.subviews {
            if let control = subview as? UIControl { return control }
            if let found = control(in: subview) { return found }
        }
        return nil
    }
}

/// The system broadcast button, embedded so it is always reachable even if the
/// labelled button above cannot forward to it.
struct SystemBroadcastPicker: UIViewRepresentable {
    let launcher: BroadcastLauncher

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(
            frame: CGRect(x: 0, y: 0, width: 44, height: 44)
        )
        picker.preferredExtension = BroadcastLauncher.extensionID
        picker.showsMicrophoneButton = true
        picker.backgroundColor = .clear
        launcher.attach(picker)
        return picker
    }

    func updateUIView(_ picker: RPSystemBroadcastPickerView, context: Context) {
        picker.preferredExtension = BroadcastLauncher.extensionID
        launcher.attach(picker)
    }
}
