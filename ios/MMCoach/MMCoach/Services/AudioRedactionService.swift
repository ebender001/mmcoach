//
//  AudioRedactionService.swift
//  MMCoach
//
//  Pipeline steps 4-5 of the PHI-hardening plan (docs/phi-hardening-plan.md):
//  maps character ranges of PHI findings in a transcript back to
//  word-level recognition timing (Map), then mutes those spans -- plus a
//  safety pad on each side -- in the recorded audio file (Redact).
//
//  Deliberately has no dependency on PHIFilterService or SFTranscriptionSegment:
//  callers translate `PHIFilterService.find(in:)`'s results into plain
//  `Range<String.Index>`, and `SFTranscriptionSegment` (word-level timing
//  from a recognition result) into `RecognizedSegment` before calling in.
//  SFTranscriptionSegment has no public initializer, so this decoupling is
//  what makes `redactionSpans` exercisable with synthetic data rather than
//  only real recognition results.
//
//  Nothing in this file sends anything over the network or is wired into
//  the live dictation flow yet -- see SpeechRecognitionService for where
//  it's actually called, and the plan doc's phased build order for what's
//  still ahead (re-transcribing the redacted file, splicing placeholders
//  into that transcript, re-screening as a defense-in-depth layer).
//

import Foundation
import AVFoundation

/// A word-level timing fact from speech recognition, decoupled from
/// `SFTranscriptionSegment` -- see the type header.
struct RecognizedSegment {
    let range: Range<String.Index>
    let timestamp: TimeInterval
    let duration: TimeInterval

    var end: TimeInterval { timestamp + duration }
}

enum AudioRedactionService {
    /// Default padding on each side of a redacted span, to absorb
    /// imprecise word-boundary timestamps and coarticulation bleed into a
    /// neighboring word (see docs/phi-hardening-plan.md's edge cases).
    static let defaultPadding: TimeInterval = 0.2

    /// For each range, the time span of every segment it overlaps
    /// (by character range), padded by `padding` seconds and clamped to
    /// `[0, audioDuration]`. A range that doesn't overlap any segment is
    /// skipped (no timing info to redact against) rather than treated as
    /// an error -- callers that care can compare their input count against
    /// the returned span count. Overlapping/adjacent padded spans (e.g.
    /// two findings close together) are merged into one, both because a
    /// duplicate mute is wasted work and because `redactAudio` assumes
    /// non-overlapping input.
    static func redactionSpans(
        for ranges: [Range<String.Index>],
        segments: [RecognizedSegment],
        padding: TimeInterval = defaultPadding,
        audioDuration: TimeInterval = .infinity
    ) -> [ClosedRange<TimeInterval>] {
        var rawSpans: [ClosedRange<TimeInterval>] = []

        for range in ranges {
            let overlapping = segments.filter { $0.range.overlaps(range) }
            guard let start = overlapping.map(\.timestamp).min(),
                  let end = overlapping.map(\.end).max() else { continue }

            let paddedStart = max(0, start - padding)
            let paddedEnd = min(audioDuration, end + padding)
            guard paddedStart < paddedEnd else { continue }
            rawSpans.append(paddedStart...paddedEnd)
        }

        return merge(rawSpans)
    }

    /// Merges overlapping or touching spans into the fewest non-overlapping
    /// ranges covering the same total time, sorted ascending.
    static func merge(_ spans: [ClosedRange<TimeInterval>]) -> [ClosedRange<TimeInterval>] {
        guard !spans.isEmpty else { return [] }
        let sorted = spans.sorted { $0.lowerBound < $1.lowerBound }
        var merged: [ClosedRange<TimeInterval>] = [sorted[0]]
        for span in sorted.dropFirst() {
            let last = merged[merged.count - 1]
            if span.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, span.upperBound)
            } else {
                merged.append(span)
            }
        }
        return merged
    }

    enum RedactionError: Error {
        case unreadableSource
        case unsupportedSampleFormat
    }

    /// Reads every frame of `file` into one buffer. NOT simply
    /// `file.read(into:)` once against a buffer sized to `file.length` --
    /// confirmed empirically that a single call can silently stop short of
    /// the requested frameCapacity (observed reading only 79872 of 80000
    /// frames on a real file, no error thrown), and a second call to
    /// `read(into:)` on the same buffer overwrites from frame 0 rather
    /// than appending, so naively looping that would also lose data. This
    /// reads in bounded chunks (with an explicit `frameCount`, which does
    /// behave as documented) into a small scratch buffer and copies each
    /// chunk's samples into the correct offset of the result buffer.
    private static func readEntireFile(_ file: AVAudioFile) throws -> AVAudioPCMBuffer {
        let format = file.processingFormat
        let totalFrames = AVAudioFrameCount(file.length)
        guard let result = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
            throw RedactionError.unreadableSource
        }
        guard totalFrames > 0 else {
            result.frameLength = 0
            return result
        }

        let chunkCapacity: AVAudioFrameCount = 32_768
        guard let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkCapacity) else {
            throw RedactionError.unreadableSource
        }
        let channelCount = Int(format.channelCount)
        var framesFilled = 0

        while file.framePosition < file.length {
            try file.read(into: chunk, frameCount: chunkCapacity)
            let chunkFrameCount = Int(chunk.frameLength)
            guard chunkFrameCount > 0 else { break } // avoid an infinite loop if nothing more is readable

            if let src = chunk.floatChannelData, let dst = result.floatChannelData {
                for channel in 0..<channelCount { (dst[channel] + framesFilled).update(from: src[channel], count: chunkFrameCount) }
            } else if let src = chunk.int16ChannelData, let dst = result.int16ChannelData {
                for channel in 0..<channelCount { (dst[channel] + framesFilled).update(from: src[channel], count: chunkFrameCount) }
            } else if let src = chunk.int32ChannelData, let dst = result.int32ChannelData {
                for channel in 0..<channelCount { (dst[channel] + framesFilled).update(from: src[channel], count: chunkFrameCount) }
            } else {
                throw RedactionError.unsupportedSampleFormat
            }
            framesFilled += chunkFrameCount
        }

        result.frameLength = AVAudioFrameCount(framesFilled)
        return result
    }

    /// Reads `sourceURL`, zeroes the sample ranges corresponding to
    /// `spans` (assumed non-overlapping -- see `redactionSpans`), and
    /// writes the result to `destinationURL` in the same PCM format.
    /// Everything outside the spans is bit-identical to the source.
    /// Builds the redacted buffer fully in memory before writing once, so
    /// a thrown error never leaves a partially-written file behind.
    static func redactAudio(sourceURL: URL, destinationURL: URL, spans: [ClosedRange<TimeInterval>]) throws {
        let sourceFile = try AVAudioFile(forReading: sourceURL)
        let buffer = try readEntireFile(sourceFile)
        let format = sourceFile.processingFormat

        let sampleRate = format.sampleRate
        let channelCount = Int(format.channelCount)
        let totalFrames = Int(buffer.frameLength)

        for span in spans {
            let startFrame = max(0, Int(span.lowerBound * sampleRate))
            let endFrame = min(totalFrames, Int(span.upperBound * sampleRate))
            guard startFrame < endFrame else { continue }
            let frameCountToZero = endFrame - startFrame

            if let channels = buffer.floatChannelData {
                for channel in 0..<channelCount {
                    (channels[channel] + startFrame).update(repeating: 0, count: frameCountToZero)
                }
            } else if let channels = buffer.int16ChannelData {
                for channel in 0..<channelCount {
                    (channels[channel] + startFrame).update(repeating: 0, count: frameCountToZero)
                }
            } else if let channels = buffer.int32ChannelData {
                for channel in 0..<channelCount {
                    (channels[channel] + startFrame).update(repeating: 0, count: frameCountToZero)
                }
            } else {
                throw RedactionError.unsupportedSampleFormat
            }
        }

        let destinationFile = try AVAudioFile(forWriting: destinationURL, settings: format.settings)
        try destinationFile.write(from: buffer)
    }
}
