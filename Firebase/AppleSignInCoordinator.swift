import Foundation
import UIKit
import AuthenticationServices
import CryptoKit
import FirebaseAuth

@MainActor
final class AppleSignInCoordinator: NSObject {
    static let shared = AppleSignInCoordinator()

    private var currentNonce: String?
    private var continuation: CheckedContinuation<AuthCredential, Error>?

    func signIn() async throws -> AuthCredential {
        let nonce = Self.randomNonceString()
        currentNonce = nonce

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self

        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            controller.performRequests()
        }
    }

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if status != errSecSuccess {
                fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(status)")
            }
            for random in randoms where remaining > 0 {
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                finish(.failure(NSError(domain: "AppleSignIn", code: -1,
                                        userInfo: [NSLocalizedDescriptionKey: "Unexpected credential type."])))
                return
            }
            guard let nonce = currentNonce else {
                finish(.failure(NSError(domain: "AppleSignIn", code: -2,
                                        userInfo: [NSLocalizedDescriptionKey: "Missing login nonce."])))
                return
            }
            guard let tokenData = appleIDCredential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                finish(.failure(NSError(domain: "AppleSignIn", code: -3,
                                        userInfo: [NSLocalizedDescriptionKey: "Unable to fetch identity token."])))
                return
            }

            var fullName: PersonNameComponents? = appleIDCredential.fullName
            if let fn = fullName,
               (fn.givenName ?? "").isEmpty && (fn.familyName ?? "").isEmpty {
                fullName = nil
            }

            let credential = OAuthProvider.appleCredential(withIDToken: idToken,
                                                           rawNonce: nonce,
                                                           fullName: fullName)
            finish(.success(credential))
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithError error: Error) {
        Task { @MainActor in
            finish(.failure(error))
        }
    }

    private func finish(_ result: Result<AuthCredential, Error>) {
        let cont = continuation
        continuation = nil
        currentNonce = nil
        switch result {
        case .success(let cred): cont?.resume(returning: cred)
        case .failure(let err):  cont?.resume(throwing: err)
        }
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            return scene?.windows.first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
        }
    }
}
