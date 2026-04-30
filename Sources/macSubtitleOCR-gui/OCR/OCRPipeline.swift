// Sources/macSubtitleOCR-gui/OCR/OCRPipeline.swift
import Foundation

@MainActor
enum OCRPipeline {
    static func run(job: SubtitleJob) async {
        // Filled in Task 14
        job.phase = .running(stage: .extracting)
    }
}
