import SwiftUI

struct AboutSettings: View {
    var body: some View {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Tidy")
                .font(.title.bold())
            Text("Version \(version) (\(build))")
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("A tidy inbox for GitHub notifications in your menu bar.")
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 260)
    }
}
