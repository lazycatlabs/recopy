import Foundation
import Observation

/// The composition root: the vault location, and the clipboard session for the open vault.
@Observable
final class AppContainer {
    @ObservationIgnored let vaults: VaultRepository
    private(set) var session: ClipboardSession? {
        didSet { session?.onToast = { [weak self] in self?.onToast?($0) } }
    }
    var errorMessage: String?
    /// Where copy and paste toasts go; set by the app delegate.
    @ObservationIgnored var onToast: ((String) -> Void)?
    /// The clipboard sessions watch; E2E runs use a private one.
    @ObservationIgnored private let makePasteboard: () -> SystemPasteboard

    init(vaults: VaultRepository = UserDefaultsVaultRepository(), pasteboard: @escaping () -> SystemPasteboard = { SystemPasteboard() }) {
        self.vaults = vaults
        makePasteboard = pasteboard
        if let url = vaults.resolveVault() { session = ClipboardSession(root: url, pasteboard: pasteboard(), copies: .copies) }
        session?.onToast = { [weak self] in self?.onToast?($0) }
    }

    func open(_ url: URL) {
        do {
            try vaults.prepare(url)
            session = ClipboardSession(root: url, pasteboard: makePasteboard(), copies: .copies)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
