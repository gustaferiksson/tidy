import Foundation

extension URL {
    var isGitHubWeb: Bool {
        guard scheme?.lowercased() == "https", let host = host()?.lowercased() else { return false }
        return host == "github.com" || host.hasSuffix(".github.com") || host.hasSuffix(".githubusercontent.com")
    }
}
