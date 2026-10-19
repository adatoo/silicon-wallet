import Foundation

/// The project's web pages. The support and privacy URLs match
/// `AppStore/metadata/en-GB/support_url.txt` and `privacy_url.txt`.
enum AppLinks {
    static let support = URL(string: "https://adatoo.github.io/silicon-wallet/support.html")!
    static let privacy = URL(string: "https://adatoo.github.io/silicon-wallet/privacy.html")!
    static let source = URL(string: "https://github.com/adatoo/silicon-wallet")!
    static let issues = URL(string: "https://github.com/adatoo/silicon-wallet/issues")!
    static let securityDesign = URL(string: "https://github.com/adatoo/silicon-wallet/blob/main/DESIGN.md#5-security")!
}
