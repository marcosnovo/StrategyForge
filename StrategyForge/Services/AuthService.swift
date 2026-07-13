//
//  AuthService.swift
//  StrategyForge
//
//  Native, dependency-free authentication. Sign in with Apple uses the system
//  AuthenticationServices flow; Google uses ASWebAuthenticationSession + OAuth 2.0
//  with PKCE (system browser, no GoogleSignIn SDK). Both return a lightweight
//  Account; the whole thing is opt-in and never required to use the app.
//

import Foundation
import AuthenticationServices
import CryptoKit
import AppKit

enum AuthError: LocalizedError {
    case cancelled
    case googleNotConfigured
    case badResponse
    case tokenExchangeFailed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Sign-in was cancelled."
        case .googleNotConfigured: return "Google sign-in isn't configured yet (missing client ID)."
        case .badResponse:
            // A common cause during early launch: the Google OAuth consent screen is
            // still "Testing"/unverified, which caps sign-in at 100 users and blocks
            // the rest here. Signing in is optional (it only enables iCloud sync), so
            // point the user at the alternative rather than dead-ending.
            return "Google couldn't complete sign-in. If Google sign-in is still being verified this can fail — try Sign in with Apple, or just continue without an account (it's optional; it only enables iCloud sync)."
        case .tokenExchangeFailed(let m):
            return "Google sign-in failed: \(m). You can use Sign in with Apple instead, or continue without an account — signing in is optional."
        }
    }
}

/// Anything that can produce an Account for a given provider.
protocol AuthenticationService {
    func signIn(with kind: AuthProviderKind) async throws -> Account
}

final class AuthService: AuthenticationService {
    private let apple = AppleAuthService()
    private let google = GoogleAuthService()

    func signIn(with kind: AuthProviderKind) async throws -> Account {
        switch kind {
        case .apple:  return try await apple.signIn()
        case .google: return try await google.signIn()
        }
    }
}

// MARK: - Sign in with Apple

private final class AppleAuthService: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    private var continuation: CheckedContinuation<Account, Error>?

    func signIn() async throws -> Account {
        try await withCheckedThrowingContinuation { cont in
            continuation = cont
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation?.resume(throwing: AuthError.badResponse)
            continuation = nil
            return
        }
        // fullName/email are only delivered on the FIRST authorization; that's fine
        // for identity because the user id is stable and always present.
        let formatter = PersonNameComponentsFormatter()
        let name = cred.fullName.map { formatter.string(from: $0) }.flatMap { $0.isEmpty ? nil : $0 }
        let account = Account(id: cred.user, provider: .apple, displayName: name, email: cred.email)
        continuation?.resume(returning: account)
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        let mapped: Error = (error as? ASAuthorizationError)?.code == .canceled ? AuthError.cancelled : error
        continuation?.resume(throwing: mapped)
        continuation = nil
    }
}

// MARK: - Google (OAuth 2.0 + PKCE, no SDK)

private final class GoogleAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {

    func signIn() async throws -> Account {
        guard Constants.Auth.isGoogleConfigured else { throw AuthError.googleNotConfigured }

        let verifier = PKCE.codeVerifier()
        let challenge = PKCE.codeChallenge(for: verifier)
        let redirectURI = Constants.Auth.googleRedirectURI
        // Callback scheme is everything before the first colon.
        let scheme = String(redirectURI.prefix(while: { $0 != ":" }))

        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            .init(name: "client_id", value: Constants.Auth.googleClientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "openid email profile"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
        ]

        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(url: comps.url!, callbackURLScheme: scheme) { url, error in
                if let url {
                    cont.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    cont.resume(throwing: AuthError.cancelled)
                } else {
                    cont.resume(throwing: error ?? AuthError.badResponse)
                }
            }
            session.presentationContextProvider = self
            session.start()
        }

        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AuthError.badResponse
        }
        return try await exchange(code: code, verifier: verifier, redirectURI: redirectURI)
    }

    private func exchange(code: String, verifier: String, redirectURI: String) async throws -> Account {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form = [
            "client_id": Constants.Auth.googleClientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI,
        ]
        request.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AuthError.tokenExchangeFailed(String(data: data, encoding: .utf8) ?? "unknown")
        }
        struct TokenResponse: Decodable { let id_token: String?; let refresh_token: String? }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let idToken = token.id_token, let claims = JWT.claims(idToken) else {
            throw AuthError.badResponse
        }
        // Persist the refresh token for later silent refresh (out of the synced store).
        if let refresh = token.refresh_token, let d = refresh.data(using: .utf8) {
            KeychainStore.set(d, for: "google.refreshToken")
        }
        return Account(
            id: claims["sub"] as? String ?? UUID().uuidString,
            provider: .google,
            displayName: claims["name"] as? String,
            email: claims["email"] as? String
        )
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}

// MARK: - PKCE + JWT helpers

private enum PKCE {
    static func codeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return base64URL(Data(hash))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private enum JWT {
    /// Decode the (unverified) claims from a JWT's payload segment. Signature is
    /// not checked because the token comes straight from Google's token endpoint
    /// over TLS and is used only for display identity, never for authorization.
    static func claims(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json
    }
}
