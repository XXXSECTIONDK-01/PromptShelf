import AppKit
import SwiftUI
import PromptUI

enum AppIdentity {
    static let creatorTag = "MADE BY ANDY CHEN"
    static let githubHandle = "XXXSECTIONDK-01"
    static let githubURL = URL(string: "https://github.com/XXXSECTIONDK-01")!
    static var icon: NSImage? { NSImage(named: "AppIconArtwork") }
}

struct CreatorCredit: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Link(destination: AppIdentity.githubURL) {
                HStack(spacing: 8) {
                    Text(AppIdentity.creatorTag).font(.system(size: 10, weight: .semibold)).tracking(1.2)
                    Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .medium))
                }.padding(.horizontal, 11).padding(.vertical, 7)
                    .foregroundStyle(AppTypography.annotation)
                    .background(AppTypography.annotation.opacity(0.07), in: Capsule())
                    .overlay(Capsule().strokeBorder(AppTypography.rule.opacity(0.6), lineWidth: 0.5))
                    .contentShape(Capsule())
            }.buttonStyle(.plain).help("在 GitHub 上查看创作者")
                .accessibilityLabel("MADE BY ANDY CHEN，在 GitHub 查看 XXXSECTIONDK-01")
            Text("GitHub · @\(AppIdentity.githubHandle)").font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}
