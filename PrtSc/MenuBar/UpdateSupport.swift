import Foundation

/// Sparkle is only usable once a real EdDSA public key replaces the placeholder in Info.plist.
enum UpdateSupport {
    static let placeholderKey = "REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY"

    static var isConfigured: Bool {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        guard let key, !key.isEmpty else { return false }
        return key != placeholderKey
    }
}
