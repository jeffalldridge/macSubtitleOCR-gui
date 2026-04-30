import Foundation

public actor OCRRunner {
    public struct Options: Sendable, Equatable {
        public var languages: String
        public var invert: Bool
        public var customWords: String?
        public var disableICorrection: Bool

        public init(languages: String = "en",
                    invert: Bool = false,
                    customWords: String? = nil,
                    disableICorrection: Bool = false) {
            self.languages = languages
            self.invert = invert
            self.customWords = customWords
            self.disableICorrection = disableICorrection
        }
    }

    public struct Output: Sendable {
        public let outputDir: URL
        public let logLines: [String]
    }

    public enum Event: Sendable {
        case logLine(String)
        case finished(Output)
        case failed(stderr: String, code: Int32)
    }

    public let binary: URL
    public init(binary: URL) {
        self.binary = binary
    }

    public func run(input: URL, options: Options) -> AsyncStream<Event> {
        AsyncStream { continuation in
            let outputDir = Self.makeOutputDir()
            let process = Process()
            process.executableURL = binary
            process.arguments = Self.arguments(input: input, outputDir: outputDir, options: options)

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // Capture log lines from stderr (the underlying tool logs there).
            // Use a serial actor-isolated buffer via a class.
            final class LineBuffer: @unchecked Sendable {
                var lines: [String] = []
                let lock = NSLock()
                func append(_ s: String) { lock.lock(); lines.append(s); lock.unlock() }
                func snapshot() -> [String] { lock.lock(); defer { lock.unlock() }; return lines }
            }
            let buffer = LineBuffer()

            let stderrHandle = stderrPipe.fileHandleForReading
            stderrHandle.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                for line in chunk.split(separator: "\n", omittingEmptySubsequences: true) {
                    let s = String(line)
                    buffer.append(s)
                    continuation.yield(.logLine(s))
                }
            }

            process.terminationHandler = { p in
                stderrHandle.readabilityHandler = nil
                let lines = buffer.snapshot()
                if p.terminationStatus == 0 {
                    continuation.yield(.finished(Output(outputDir: outputDir, logLines: lines)))
                } else {
                    continuation.yield(.failed(stderr: lines.joined(separator: "\n"), code: p.terminationStatus))
                }
                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                if process.isRunning {
                    process.terminate()
                }
            }

            do {
                try process.run()
            } catch {
                continuation.yield(.failed(stderr: error.localizedDescription, code: -1))
                continuation.finish()
            }
        }
    }

    static func arguments(input: URL, outputDir: URL, options: Options) -> [String] {
        var args = [input.path, outputDir.path, "--languages", options.languages]
        if options.invert { args.append("--invert") }
        if let words = options.customWords, !words.isEmpty {
            args.append(contentsOf: ["--custom-words", words])
        }
        if options.disableICorrection { args.append("--disable-i-correction") }
        return args
    }

    static func makeOutputDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macSubtitleOCR-gui", isDirectory: true)
            .appendingPathComponent("out-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
