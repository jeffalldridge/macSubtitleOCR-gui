// Sources/macSubtitleOCR-gui/OCR/OCRPipeline.swift
import Foundation

@MainActor
enum OCRPipeline {
    static func run(job: SubtitleJob) async {
        guard let input = job.input,
              let track = job.selectedTrack,
              let toolchain = ToolchainProbe.mkvtoolnix() else {
            job.phase = .failed(message: "Internal error: missing input, track, or toolchain.")
            return
        }

        let binary: URL
        do {
            binary = try BundledBinary.resolve()
        } catch {
            job.phase = .failed(message: error.localizedDescription)
            return
        }

        // Stage 1: Extract (only for MKV; .sup/.sub passes through)
        var ocrInput = input
        let ext = input.pathExtension.lowercased()
        if ext == "mkv" || ext == "mks" {
            job.phase = .running(stage: .extracting)
            do {
                let extractor = MKVToolNixExtractor(mkvextractPath: toolchain.mkvextract)
                ocrInput = try await extractor.extract(input: input, trackID: track.id)
            } catch {
                job.phase = .failed(message: error.localizedDescription)
                return
            }
        }

        // Stage 2: OCR
        job.phase = .running(stage: .ocr)
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
                job.phase = .failed(message: "macSubtitleOCR exited with code \(code).")
                return
            }
        }

        guard let dir = producedDir else {
            job.phase = .failed(message: "macSubtitleOCR produced no output.")
            return
        }

        // Stage 3: Finalize
        job.phase = .running(stage: .finalizing)
        do {
            let finalURL = try SRTFinalizer.finalize(
                producedSRTDir: dir,
                inputURL: input,
                language: track.language ?? job.options.languages.split(separator: ",").first.map(String.init)
            )
            // Clean up temp extraction file if we made one
            if ocrInput != input { try? FileManager.default.removeItem(at: ocrInput) }
            try? FileManager.default.removeItem(at: dir)
            job.phase = .done(output: finalURL)
        } catch {
            job.phase = .failed(message: error.localizedDescription)
        }
    }
}
