import Foundation

public struct ProcessResult: Sendable {
    public let stdout: Data
    public let stderr: Data
    public let terminationStatus: Int32
}

public enum ProcessRunnerError: Error, LocalizedError {
    case launchFailed(URL, underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .launchFailed(let executable, let error):
            "Could not launch \(executable.lastPathComponent): \(error.localizedDescription)"
        }
    }
}

public enum ProcessRunner {
    public static func run(executable: URL, arguments: [String]) async throws -> ProcessResult {
        let process = Process()
        let processBox = ProcessBox(process)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                let output = LockedData()
                let finish = ContinuationBox(continuation)

                process.executableURL = executable
                process.arguments = arguments
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                let stdoutHandle = stdoutPipe.fileHandleForReading
                let stderrHandle = stderrPipe.fileHandleForReading

                stdoutHandle.readabilityHandler = { handle in
                    output.appendStdout(handle.availableData)
                }
                stderrHandle.readabilityHandler = { handle in
                    output.appendStderr(handle.availableData)
                }

                process.terminationHandler = { terminatedProcess in
                    stdoutHandle.readabilityHandler = nil
                    stderrHandle.readabilityHandler = nil
                    output.appendStdout(stdoutHandle.readDataToEndOfFile())
                    output.appendStderr(stderrHandle.readDataToEndOfFile())
                    let snapshot = output.snapshot()
                    finish.resume(.success(ProcessResult(
                        stdout: snapshot.stdout,
                        stderr: snapshot.stderr,
                        terminationStatus: terminatedProcess.terminationStatus
                    )))
                }

                do {
                    try process.run()
                } catch {
                    stdoutHandle.readabilityHandler = nil
                    stderrHandle.readabilityHandler = nil
                    finish.resume(.failure(ProcessRunnerError.launchFailed(executable, underlying: error)))
                }
            }
        } onCancel: {
            processBox.terminate()
        }
    }
}

private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process

    init(_ process: Process) {
        self.process = process
    }

    func terminate() {
        lock.lock()
        defer { lock.unlock() }
        if process.isRunning {
            process.terminate()
        }
    }
}

private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()

    func appendStdout(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        stdout.append(data)
        lock.unlock()
    }

    func appendStderr(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        stderr.append(data)
        lock.unlock()
    }

    func snapshot() -> (stdout: Data, stderr: Data) {
        lock.lock()
        defer { lock.unlock() }
        return (stdout, stderr)
    }
}

private final class ContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ProcessResult, Error>?

    init(_ continuation: CheckedContinuation<ProcessResult, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<ProcessResult, Error>) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        lock.unlock()

        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
