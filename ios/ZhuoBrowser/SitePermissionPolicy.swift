import Foundation

enum SitePermissionDecision: Int, Codable {
    case prompt = 0
    case allow = 1
    case deny = 2

    var label: String {
        switch self {
        case .prompt: return "询问"
        case .allow: return "允许"
        case .deny: return "拒绝"
        }
    }
}

enum SitePermissionKind: String, Codable, CaseIterable {
    case camera
    case microphone
    case location

    var label: String {
        switch self {
        case .camera: return "相机"
        case .microphone: return "麦克风"
        case .location: return "位置"
        }
    }
}

struct SitePermission: Identifiable, Equatable, Codable {
    var origin: String
    var camera: SitePermissionDecision
    var microphone: SitePermissionDecision
    var location: SitePermissionDecision

    var id: String { origin }

    static func empty(_ origin: String) -> SitePermission {
        SitePermission(origin: origin, camera: .prompt, microphone: .prompt, location: .prompt)
    }

    func decision(for kind: SitePermissionKind) -> SitePermissionDecision {
        switch kind {
        case .camera: return camera
        case .microphone: return microphone
        case .location: return location
        }
    }

    mutating func set(_ kind: SitePermissionKind, _ decision: SitePermissionDecision) {
        switch kind {
        case .camera: camera = decision
        case .microphone: microphone = decision
        case .location: location = decision
        }
    }
}

enum SitePermissionPolicy {
    static func toggledDecision(from current: SitePermissionDecision) -> SitePermissionDecision {
        current == .allow ? .deny : .allow
    }

    static func decision(stored: SitePermission?, kinds: [SitePermissionKind]) -> SitePermissionDecision {
        guard let stored else {
            return .prompt
        }
        var result = SitePermissionDecision.allow
        for kind in kinds {
            let decision = stored.decision(for: kind)
            if decision == .deny {
                return .deny
            }
            if decision == .prompt {
                result = .prompt
            }
        }
        return result
    }

    static func apply(
        _ list: [SitePermission],
        origin: String,
        kinds: [SitePermissionKind],
        decision: SitePermissionDecision
    ) -> [SitePermission] {
        var next = list
        let index = next.firstIndex(where: { $0.origin == origin })
        var stored = index.flatMap { next[safe: $0] } ?? SitePermission.empty(origin)
        for kind in kinds {
            stored.set(kind, decision)
        }
        if let index {
            next[index] = stored
        } else {
            next.append(stored)
        }
        return next
    }

    static func origin(protocol scheme: String, host: String, port: Int) -> String {
        if scheme.isEmpty || host.isEmpty {
            return ""
        }
        if port == 0 || port == 80 || port == 443 {
            return "\(scheme)://\(host)"
        }
        return "\(scheme)://\(host):\(port)"
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
