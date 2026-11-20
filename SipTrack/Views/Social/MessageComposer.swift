import MessageUI
import SwiftUI
import UIKit

/// The Messages composer with one recipient and the text filled in, for
/// inviting a contact when WhatsApp isn't installed. Check
/// `MFMessageComposeViewController.canSendText()` before showing it.
///
/// `onFinish` gets `.sent`, `.cancelled` or `.failed`; the presenter closes it.
struct MessageComposer: UIViewControllerRepresentable {
    let recipient: String
    let body: String
    let onFinish: (MessageComposeResult) -> Void

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.recipients = [recipient]
        controller.body = body
        controller.messageComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        private let onFinish: (MessageComposeResult) -> Void

        init(onFinish: @escaping (MessageComposeResult) -> Void) {
            self.onFinish = onFinish
        }

        // nonisolated whether or not the SDK marks the protocol main-actor;
        // UIKit calls it on the main thread.
        nonisolated func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                                      didFinishWith result: MessageComposeResult) {
            MainActor.assumeIsolated {
                onFinish(result)
            }
        }
    }
}
