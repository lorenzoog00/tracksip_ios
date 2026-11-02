import UIKit

/// Finding the controller to present something from.
///
/// This was written out by hand in six places, each slightly differently, and
/// every variant was wrong in its own way:
///
/// - `connectedScenes.first as? UIWindowScene` — `connectedScenes` is a **Set**.
///   Its first element is whatever the hash order gives, which may be a
///   background scene, or not a window scene at all, in which case the whole
///   lookup silently gives up.
/// - `scene.windows.first` — the first window is not necessarily the visible
///   one. An alert, a keyboard or a system overlay can own its own window.
/// - Returning the **root** controller when something is already presented on
///   top of it. UIKit refuses to present onto a controller that is already
///   presenting, so the call quietly does nothing. That is how deleting an
///   account failed, and the same shape sits in the consent form and the share
///   sheet.
///
/// The right answer is not the same everywhere, which is why there are two of
/// them: `topMost()` for something being presented **now**, and `root()` for a
/// reference that has to stay valid **later**.
@MainActor
enum PresentationAnchor {

    /// The controller a sheet can be presented from right now.
    ///
    /// Use for anything that presents immediately: consent forms, ads, share
    /// sheets, sign-in flows.
    static func topMost() -> UIViewController? {
        guard let root = rootOfKeyWindow() else { return nil }
        return topMost(from: root)
    }

    /// The stable bottom of the stack.
    ///
    /// Use when the controller is **stored** rather than presented on — a
    /// banner ad keeps this reference for the whole time it is on screen, and
    /// handing it whatever happened to be on top at creation time leaves it
    /// pointing at a sheet that may be long gone by the time the ad is tapped.
    static func root() -> UIViewController? {
        rootOfKeyWindow()
    }

    /// `topMost()`, but first waits out anything in the middle of being
    /// dismissed — the case where a button inside a sheet or dialog opens
    /// another one, and the old one has not finished leaving yet.
    static func waitingForDismissal(
        timeout: Duration = .seconds(2)
    ) async throws -> UIViewController {
        guard let root = rootOfKeyWindow() else {
            throw NSError(
                domain: "PresentationAnchor", code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Could not open the next screen. Please try again."]
            )
        }
        let step = Duration.milliseconds(50)
        var waited = Duration.zero
        while waited < timeout {
            let top = topMost(from: root)
            if top.presentedViewController == nil { return top }
            try? await Task.sleep(for: step)
            waited += step
        }
        // Waited long enough. Hand back what is on top and let UIKit report
        // what it thinks rather than blocking here any longer.
        return topMost(from: root)
    }

    // MARK: -

    private static func rootOfKeyWindow() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows.first { $0.isKeyWindow }?
            .rootViewController
    }

    /// Stops at anything being dismissed, so a caller that can wait knows to
    /// wait rather than targeting a controller that is about to disappear.
    private static func topMost(from root: UIViewController) -> UIViewController {
        var top = root
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}
