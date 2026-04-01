import SwiftUI

struct StashesView: View {
    @Environment(GitService.self) private var gitService

    var body: some View {
        Group {
            if gitService.isLoading {
                loadingState
            } else if gitService.stashes.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(gitService.stashes) { stash in
                            StashRowView(stash: stash)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "archivebox")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.secondary)
            Text("No stashes found")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
