import Foundation

enum AppInformation {
    static let tagline = "浏览器应该是一张安静的纸。"
    static let filingNumber = "鄂ICP备2024064800号-14A"
    static let termsURL = URL(string: "https://browser.youdroid.top/terms.html")!
    static let privacyURL = URL(string: "https://browser.youdroid.top/privacy.html")!
    static let supportURL = URL(string: "mailto:youdroid2048@gmail.com")!

    static func versionLabel(bundle: Bundle = .main) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return "\(version) (\(build))"
    }
}
