import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import UIKit

// Session token lives in the Keychain: it authorizes reports, claims, and
// list changes, so UserDefaults is not the place for it.
enum Keychain {
    private static let service = "com.knowyourcoffee.app.session"

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ key: String, _ value: String) {
        delete(key)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum CodeSignInMethod: String, Identifiable {
    case phone, email

    var id: String { rawValue }
}

enum AuthError: LocalizedError {
    case notConfigured
    case cancelled
    case flow(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            """
            Google sign-in isn't set up for the app yet. Create an iOS OAuth client \
            in the Google Cloud project (bundle id com.knowyourcoffee.app), then put \
            its client ID in Info.plist under GoogleOAuthClientID and in the backend \
            env as GOOGLE_OAUTH_IOS_CLIENT_ID.
            """
        case .cancelled: "Sign-in was cancelled."
        case .flow(let message): message
        }
    }
}

@MainActor
@Observable
final class AuthStore {
    static let shared = AuthStore()

    private(set) var user: User?
    private(set) var token: String?

    static let tokenKey = "sessionToken"
    private static let userKey = "sessionUser"

    private init() {
        token = Keychain.read(Self.tokenKey)
        if let data = UserDefaults.standard.data(forKey: Self.userKey) {
            user = try? JSONDecoder().decode(User.self, from: data)
        }
        if token == nil { user = nil }
    }

    var isSignedIn: Bool { token != nil }

    // Native OAuth: authorization-code + PKCE against the iOS OAuth client,
    // then the backend swaps Google's ID token for its own session token.
    // No Google SDK; ASWebAuthenticationSession is the system surface.
    func signIn() async throws {
        guard let clientID = Self.iosClientID else { throw AuthError.notConfigured }

        let verifier = Self.randomURLSafe(43)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        // iOS OAuth clients redirect to the reversed client id scheme.
        let scheme = clientID.split(separator: ".").reversed().joined(separator: ".")
        let redirectURI = "\(scheme):/oauth2redirect"

        var authURL = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        authURL.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        let callback = try await Self.present(url: authURL.url!, callbackScheme: scheme)
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value
        else {
            throw AuthError.flow("Google returned no authorization code.")
        }

        let idToken = try await Self.exchangeCode(
            code, clientID: clientID, redirectURI: redirectURI, verifier: verifier
        )

        let payload = try await CoffeeAPI.signInWithGoogle(idToken: idToken)
        store(payload)
    }

    // MARK: Sign in with Apple

    func signInWithApple(identityToken: String, name: String?) async throws {
        let payload = try await CoffeeAPI.signInWithApple(identityToken: identityToken, name: name)
        store(payload)
    }

    // MARK: One-time code sign-in (SMS or email)

    /// Sends the code. Returns it only against a dev backend without a provider.
    func startCodeSignIn(method: CodeSignInMethod, identifier: String) async throws -> String? {
        try await CoffeeAPI.startCodeSignIn(method: method, identifier: identifier)
    }

    func signIn(method: CodeSignInMethod, identifier: String, code: String) async throws {
        let payload = try await CoffeeAPI.signInWithCode(method: method, identifier: identifier, code: code)
        store(payload)
    }

    private func store(_ payload: AuthPayload) {
        token = payload.token
        user = payload.user
        Keychain.write(Self.tokenKey, payload.token)
        UserDefaults.standard.set(try? JSONEncoder().encode(payload.user), forKey: Self.userKey)
    }

    func signOut() {
        token = nil
        user = nil
        Keychain.delete(Self.tokenKey)
        UserDefaults.standard.removeObject(forKey: Self.userKey)
    }

    // The server rejected our session (restart without SESSION_SECRET, expiry).
    func sessionExpired() {
        signOut()
    }

    static var iosClientID: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "GoogleOAuthClientID") as? String
        return value?.isEmpty == false ? value : nil
    }

    // MARK: OAuth plumbing

    private static func exchangeCode(
        _ code: String, clientID: String, redirectURI: String, verifier: String
    ) async throws -> String {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")
        request.httpBody = [
            "code": code,
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
        ]
        .map { "\($0)=\($1.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $1)" }
        .joined(separator: "&")
        .data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        struct TokenResponse: Decodable { let id_token: String? }
        guard let idToken = try? JSONDecoder().decode(TokenResponse.self, from: data).id_token else {
            throw AuthError.flow("Could not exchange the Google code for a token.")
        }
        return idToken
    }

    private static func present(url: URL, callbackScheme: String) async throws -> URL {
        let presenter = WebAuthPresenter()
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if case ASWebAuthenticationSessionError.canceledLogin? = error {
                    continuation.resume(throwing: AuthError.cancelled)
                } else {
                    continuation.resume(throwing: AuthError.flow(error?.localizedDescription ?? "Sign-in failed."))
                }
            }
            session.presentationContextProvider = presenter
            // Keep the presenter alive for the session's lifetime.
            objc_setAssociatedObject(session, "presenter", presenter, .OBJC_ASSOCIATION_RETAIN)
            session.start()
        }
    }

    private static func randomURLSafe(_ length: Int) -> String {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        return String((0..<length).map { _ in alphabet.randomElement()! })
    }
}

private final class WebAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }
}
