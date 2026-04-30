import Foundation

@MainActor
enum OCRPipeline {
    static func run(job: SubtitleJob) async {
        guard let input = job.input,
              !job.selectedTracks.isEmpty,
              let toolchain = ToolchainProbe.mkvtoolnix() else {
            job.phase = .failed(message: "Internal error: missing input, tracks, or toolchain.")
            return
        }

        let binary: URL
        do {
            binary = try BundledBinary.resolve()
        } catch {
            job.phase = .failed(message: error.localizedDescription)
            return
        }

        let ext = input.pathExtension.lowercased()
        let isContainer = (ext == "mkv" || ext == "mks")

        let orderedTracks = job.selectedTracks.sorted { $0.id < $1.id }
        var outputs: [URL] = []

        for (index, track) in orderedTracks.enumerated() {
            // Stage 1: Extract (only for MKV; .sup/.sub passes through)
            var ocrInput = input
            if isContainer {
                job.phase = .running(stage: .extracting,
                                     currentTrackIndex: index,
                                     totalTracks: orderedTracks.count)
                do {
                    let extractor = MKVToolNixExtractor(mkvextractPath: toolchain.mkvextract)
                    ocrInput = try await extractor.extract(input: input, trackID: track.id)
                } catch {
                    job.phase = .failed(message: "Track \(track.id): \(error.localizedDescription)")
                    return
                }
            }

            // Stage 2: OCR
            job.phase = .running(stage: .ocr, currentTrackIndex: index, totalTracks: orderedTracks.count)
            let runner = OCRRunner(binary: binary)
            let stream = await runner.run(input: ocrInput, options: job.options)

            var producedDir: URL?
            for await event in stream {
                switch event {
                case .logLine(let line):
                    job.appendLog(line)
                case .finished(let out):
                    producedDir = out.outputDir
                case .failed(let stderr, let code):
                    job.appendLog(stderr)
                    job.phase = .failed(message: "Track \(track.id): macSubtitleOCR exited with code \(code).")
                    return
                }
            }

            guard let dir = producedDir else {
                job.phase = .failed(message: "Track \(track.id): macSubtitleOCR produced no output.")
                return
            }

            // Stage 3: Finalize
            job.phase = .running(stage: .finalizing,
                                 currentTrackIndex: index,
                                 totalTracks: orderedTracks.count)
            do {
                let lang = track.language ?? job.options.languages.split(separator: ",").first.map(String.init)
                let finalURL = try SRTFinalizer.finalize(
                    producedSRTDir: dir,
                    inputURL: input,
                    language: lang,
                    trackName: track.name
                )
                outputs.append(finalURL)
                if ocrInput != input { try? FileManager.default.removeItem(at: ocrInput) }
                try? FileManager.default.removeItem(at: dir)
            } catch {
                job.phase = .failed(message: "Track \(track.id): \(error.localizedDescription)")
                return
            }
        }

        job.phase = .done(outputs: outputs)
    }
}
