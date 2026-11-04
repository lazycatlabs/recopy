import Foundation

/// Where feedback and bug reports go. Bug reports carry the app and macOS versions so they can be reproduced.
nonisolated enum SupportLinks {
    static let email = "help.me@lazycatlabs.com"
    static let website = URL(string: "https://recopy.lazycatlabs.com")!
    static let sourceCode = URL(string: "https://github.com/lazycatlabs/recopy")!
    static let license = URL(string: "https://github.com/lazycatlabs/recopy/blob/main/LICENSE")!

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    static func feedback() -> URL? {
        mail(subject: L(.feedbackSubject), body: "")
    }

    static func bugReport(appVersion: String = appVersion,
                          systemVersion: String = ProcessInfo.processInfo.operatingSystemVersionString) -> URL? {
        mail(subject: L(.bugReportSubject), body: L(.bugReportBody(appVersion, systemVersion)))
    }

    static func mail(subject: String, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: body)]
            .filter { !($0.value ?? "").isEmpty }
        return components.url
    }
}

/// Ways to sponsor ReCopy, the same as `.github/FUNDING.yml`.
nonisolated enum Sponsor: String, CaseIterable, Identifiable {
    case github, buyMeACoffee, kofi, paypal, saweria

    var id: Self { self }

    var url: URL {
        switch self {
        case .github: URL(string: "https://github.com/sponsors/Lzyct")!
        case .buyMeACoffee: URL(string: "https://buymeacoffee.com/Lzyct")!
        case .kofi: URL(string: "https://ko-fi.com/Lzyct")!
        case .paypal: URL(string: "https://paypal.me/ukieTux")!
        case .saweria: URL(string: "https://saweria.co/Lzyct")!
        }
    }

    var title: String {
        switch self {
        case .github: L(.sponsorGitHub)
        case .buyMeACoffee: L(.sponsorBuyMeACoffee)
        case .kofi: L(.sponsorKofi)
        case .paypal: L(.sponsorPayPal)
        case .saweria: L(.sponsorSaweria)
        }
    }

    var subtitle: String? {
        switch self {
        case .github: L(.sponsorGitHubSubtitle)
        case .saweria: L(.sponsorSaweriaSubtitle)
        default: nil
        }
    }

    var symbol: String {
        switch self {
        case .github: "heart"
        case .buyMeACoffee: "cup.and.saucer"
        case .kofi: "mug"
        case .paypal: "creditcard"
        case .saweria: "gift"
        }
    }
}
