import DiskInventoryCore
import Foundation
import Observation

@MainActor @Observable
final class ScanModel {
    enum State {
        case idle
        case scanning(url: URL, files: Int, bytes: Int64)
        case done(url: URL, root: FileNode, duration: Duration)
        case failed(url: URL, message: String)
    }

    private(set) var state: State = .idle
    var selection: FileNode?

    private var scanTask: Task<Void, Never>?

    var root: FileNode? {
        if case .done(_, let root, _) = state { root } else { nil }
    }

    var isScanning: Bool {
        if case .scanning = state { true } else { false }
    }

    func scan(_ url: URL) {
        cancel()
        selection = nil
        state = .scanning(url: url, files: 0, bytes: 0)

        let progress = ScanProgress()
        let started = ContinuousClock.now
        scanTask = Task {
            let poller = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(150))
                    if case .scanning = state {
                        state = .scanning(url: url, files: progress.fileCount, bytes: progress.byteCount)
                    }
                }
            }
            defer { poller.cancel() }

            do {
                let root = try await Task.detached(priority: .userInitiated) {
                    try await Scanner().scan(url, progress: progress)
                }.value
                guard !Task.isCancelled else { return }
                state = .done(url: url, root: root, duration: ContinuousClock.now - started)
            } catch is CancellationError {
                state = .idle
            } catch {
                state = .failed(url: url, message: String(describing: error))
            }
        }
    }

    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        if isScanning { state = .idle }
    }
}

enum Format {
    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    static func count(_ n: Int) -> String {
        n.formatted(.number)
    }
}
