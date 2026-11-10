import SwiftUI

/// Where this copy of ReCopy comes from. The Mac App Store build is compiled with `APP_STORE` (see `fastlane/Fastfile`);
/// GitHub and Homebrew get the other one.
nonisolated enum Distribution {
    #if APP_STORE
    static let isAppStore = true
    #else
    static let isAppStore = false
    #endif
}

extension View {
    /// Leaves this view out of the App Store build. Use it for anything App Review rejects: sponsor and donation links,
    /// links to pages that have them (the GitHub repository), GitHub downloads and self-updates.
    @ViewBuilder func hiddenInAppStore() -> some View {
        if !Distribution.isAppStore { self }
    }
}
