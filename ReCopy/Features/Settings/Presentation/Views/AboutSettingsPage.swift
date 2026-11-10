import SwiftUI

struct AboutSettingsPage: View {
    var body: some View {
        SettingsGroup(L(.settingsAbout), footer: L(.aboutLicenseFooter)) {
            SettingsRow(L(.aboutVersion), symbol: "info.circle") {
                Text(SupportLinks.appVersion).foregroundStyle(.secondary).textSelection(.enabled)
            }
            SettingsRow(L(.aboutLicense), symbol: "checkmark.seal") {
                Link(L(.aboutLicenseName), destination: SupportLinks.license).accessibilityIdentifier("settings.license")
            }
            // The repository links to sponsors and the GitHub download (App Review 3.1.1).
            SettingsRow(L(.aboutSourceCode), symbol: "chevron.left.forwardslash.chevron.right") {
                Link(L(.aboutSourceCode), destination: SupportLinks.sourceCode)
            }
            .hiddenInAppStore()
            if let url = SupportLinks.feedback() {
                SettingsRow(L(.supportFeedback), symbol: "bubble.left") { Link(L(.supportFeedback), destination: url) }
            }
            if let url = SupportLinks.bugReport() {
                SettingsRow(L(.supportBugReport), symbol: "ladybug") { Link(L(.supportBugReport), destination: url) }
            }
            // The website offers the GitHub download and sponsor links.
            SettingsRow(L(.supportWebsite), symbol: "safari") { Link(L(.supportWebsite), destination: SupportLinks.website) }
                .hiddenInAppStore()
        }
        // App Review only allows tips through In-App Purchase.
        SettingsGroup(L(.sponsorTitle), footer: L(.sponsorFooter)) {
            ForEach(Sponsor.allCases) { sponsor in
                SettingsRow(sponsor.title, symbol: sponsor.symbol, subtitle: sponsor.subtitle) {
                    Link(L(.sponsorSupport), destination: sponsor.url)
                        .accessibilityLabel(L(.sponsorSupportOn(sponsor.title)))
                        .accessibilityIdentifier(sponsor == .github ? "settings.sponsor" : "settings.sponsor.\(sponsor.rawValue)")
                }
            }
        }
        .hiddenInAppStore()
    }
}
