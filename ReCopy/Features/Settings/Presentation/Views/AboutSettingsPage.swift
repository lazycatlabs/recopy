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
            SettingsRow(L(.aboutSourceCode), symbol: "chevron.left.forwardslash.chevron.right") {
                Link(L(.aboutSourceCode), destination: SupportLinks.sourceCode)
            }
            if let url = SupportLinks.feedback() {
                SettingsRow(L(.supportFeedback), symbol: "bubble.left") { Link(L(.supportFeedback), destination: url) }
            }
            if let url = SupportLinks.bugReport() {
                SettingsRow(L(.supportBugReport), symbol: "ladybug") { Link(L(.supportBugReport), destination: url) }
            }
            SettingsRow(L(.supportWebsite), symbol: "safari") { Link(L(.supportWebsite), destination: SupportLinks.website) }
        }
        // App Review only allows tips through In-App Purchase.
        #if !APP_STORE
        SettingsGroup(L(.sponsorTitle), footer: L(.sponsorFooter)) {
            ForEach(Sponsor.allCases) { sponsor in
                SettingsRow(sponsor.title, symbol: sponsor.symbol, subtitle: sponsor.subtitle) {
                    Link(L(.sponsorSupport), destination: sponsor.url)
                        .accessibilityLabel(L(.sponsorSupportOn(sponsor.title)))
                        .accessibilityIdentifier(sponsor == .github ? "settings.sponsor" : "settings.sponsor.\(sponsor.rawValue)")
                }
            }
        }
        #endif
    }
}
