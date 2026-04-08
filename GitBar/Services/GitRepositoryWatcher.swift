import Foundation

final class GitRepositoryWatcher {
    let onChange: () -> Void
    private var sources: [DispatchSourceFileSystemObject] = []
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.5
    private let queue = DispatchQueue(label: "com.gitbar.repository-watcher")

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func start(repoPath: String) {
        queue.sync { self._stop() }
        let gitURL = URL(fileURLWithPath: repoPath).appendingPathComponent(".git")
        let subpaths = ["", "HEAD", "refs", "refs/heads", "refs/stash", "refs/tags", "worktrees"]
        let pathsToWatch = subpaths.map { gitURL.appendingPathComponent($0).path }
        queue.sync {
            for path in pathsToWatch {
                guard FileManager.default.fileExists(atPath: path) else { continue }
                let fd = open(path, O_EVTONLY)
                guard fd >= 0 else { continue }
                let source = DispatchSource.makeFileSystemObjectSource(
                    fileDescriptor: fd,
                    eventMask: [.write, .rename, .delete],
                    queue: self.queue
                )
                source.setEventHandler { [weak self] in self?.scheduleRefresh() }
                source.setCancelHandler { close(fd) }
                source.resume()
                self.sources.append(source)
            }
        }
    }

    func stop() {
        queue.sync { _stop() }
    }

    private func _stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        sources.forEach { $0.cancel() }
        sources.removeAll()
    }

    private func scheduleRefresh() {
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.onChange()
        }
        debounceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: item)
    }

    deinit {
        _stop()
    }
}
