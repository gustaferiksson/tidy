import SwiftUI

struct AboutSettings: View {
    var body: some View {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        VStack(spacing: 4) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Tidy")
                .font(.title.bold())
            Text("Version \(version) (\(build))")
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("A tidy inbox for GitHub notifications in your menu bar.")
                .padding(.top, 8)
            Link("github.com/gustaferiksson/tidy", destination: URL(string: "https://github.com/gustaferiksson/tidy")!)
                .padding(.top, 4)
            Link("State icons: GitHub Octicons (MIT License)", destination: URL(string: "https://github.com/primer/octicons/blob/main/LICENSE")!)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 280)
    }
}
