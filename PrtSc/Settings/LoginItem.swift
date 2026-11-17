import ServiceManagement

/// Abstraction over the login item so SettingsStore can be tested without touching the system.
@MainActor
protocol LoginItemControlling {
    /// True when PrtSc is registered to launch at login (including "awaiting user approval").
    var isRegistered: Bool { get }
    /// True when macOS wants the user to approve the login item in System Settings.
    var requiresApproval: Bool { get }
    func setRegistered(_ registered: Bool) throws
}

/// SMAppService.mainApp-backed login item.
@MainActor
struct SystemLoginItem: LoginItemControlling {
    private var service: SMAppService { .mainApp }

    var isRegistered: Bool {
        switch service.status {
        case .enabled, .requiresApproval: true
        default: false
        }
    }

    var requiresApproval: Bool { service.status == .requiresApproval }

    func setRegistered(_ registered: Bool) throws {
        if registered {
            if service.status != .enabled { try service.register() }
        } else if service.status != .notRegistered && service.status != .notFound {
            try service.unregister()
        }
    }
}
