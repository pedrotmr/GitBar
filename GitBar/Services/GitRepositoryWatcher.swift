import Foundation

final class GitRepositoryWatcher {
    let onChange: () -> Void
    private var sources: [DispatchSourceFileSystemObject] = []
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.5

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func start(repoPath: String) {
        stop()
        let gitURL = URL(fileURLWithPath: repoPath).appendingPathComponent(".git")
        let subpaths = ["", "refs", "refs/heads", "worktrees"]
        let pathsToWatch = subpaths.map { gitURL.appendingPathComponent($0).path }
        for path in pathsToWatch {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .rename, .delete],
                queue: .global()
            )
            source.setEventHandler { [weak self] in self?.scheduleRefresh() }
            source.setCancelHandler { close(fd) }
            source.resume()
            sources.append(source)
        }
    }

    func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        sources.forEach { $0.cancel() }
        sources.removeAll()
    }

    private func scheduleRefresh() {
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.onChange() }
        debounceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: item)
    }

    deinit {
        stop()
    }
}
