//
//  AudioRedactionService.swift
//  MMCoach
//
//  Pipeline steps 4-5-7 of the PHI-hardening plan (docs/phi-hardening-plan.md):
//  maps character ranges of PHI findings in a transcript back to
//  word-level recognition timing (Map), mutes those spans -- plus a safety
//  pad on each side -- in the recorded audio file (Redact), and once the
//  redacted file has been re-transcribed, splices a placeholder back into
//  that new transcript at each span's position (Splice) so a redacted
//  span isn't just silently missing.
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
    /// Tuned down from an initial 0.2s after real-hardware testing: when
    /// two PHI items are spoken close together, padding on both sides of
    /// both spans can consume most of the real (non-PHI) speech between
    /// them, leaving only a stray word fragment in the final transcript
    /// (observed: "who lives in" between a name and a location reduced to
    /// just "Lives"). A judgment call, not a provable fix -- 0.15s still
    /// covers meaningful coarticulation bleed/timestamp imprecision, just
    /// with less margin than before.
    static let defaultPadding: TimeInterval = 0.15

    /// A redacted time span plus which tag(s) (e.g. PHI categories) it
    /// represents -- a merge of two nearby findings (see `redactionSpans`)
    /// can carry more than one, which is why this is a `Set` rather than
    /// a single value.
    struct TaggedRedactionSpan<Tag: Hashable> {
        let span: ClosedRange<TimeInterval>
        let tags: Set<Tag>
    }

    /// For each tagged range, the time span of every segment it overlaps
    /// (by character range), padded by `padding` seconds and clamped to
    /// `[0, audioDuration]`. A range that doesn't overlap any segment is
    /// skipped (no timing info to redact against) rather than treated as
    /// an error -- callers that care can compare their input count against
    /// the returned span count. Overlapping/adjacent padded spans (e.g.
    /// two findings close together) are merged into one -- both because a
    /// duplicate mute is wasted work and because `redactAudio` assumes
    /// non-overlapping input -- with their tags unioned, so a merged span
    /// remembers every category it covers (see `splicePlaceholders`).
    /// Generic over `Tag` (rather than hard-coding a PHI-specific type) so
    /// this stays a plain timing/text utility -- callers decide what a
    /// "tag" means (PHIFinding.Category in practice).
    static func redactionSpans<Tag: Hashable>(
        for taggedRanges: [(range: Range<String.Index>, tag: Tag)],
        segments: [RecognizedSegment],
        padding: TimeInterval = defaultPadding,
        audioDuration: TimeInterval = .infinity
    ) -> [TaggedRedactionSpan<Tag>] {
        var rawSpans: [(span: ClosedRange<TimeInterval>, tag: Tag)] = []

        for (range, tag) in taggedRanges {
            let overlapping = segments.filter { $0.range.overlaps(range) }
            guard let start = overlapping.map(\.timestamp).min(),
                  let end = overlapping.map(\.end).max() else { continue }

            let paddedStart = max(0, start - padding)
            let paddedEnd = min(audioDuration, end + padding)
            guard paddedStart < paddedEnd else { continue }
            rawSpans.append((paddedStart...paddedEnd, tag))
        }

        return mergeTagged(rawSpans)
    }

    /// Merges overlapping or touching spans into the fewest non-overlapping
    /// ranges covering the same total time, sorted ascending, unioning tags
    /// for anything that gets merged together.
    private static func mergeTagged<Tag: Hashable>(_ spans: [(span: ClosedRange<TimeInterval>, tag: Tag)]) -> [TaggedRedactionSpan<Tag>] {
        guard !spans.isEmpty else { return [] }
        let sorted = spans.sorted { $0.span.lowerBound < $1.span.lowerBound }
        var merged: [TaggedRedactionSpan<Tag>] = [TaggedRedactionSpan(span: sorted[0].span, tags: [sorted[0].tag])]
        for entry in sorted.dropFirst() {
            let last = merged[merged.count - 1]
            if entry.span.lowerBound <= last.span.upperBound {
                let combinedSpan = last.span.lowerBound...max(last.span.upperBound, entry.span.upperBound)
                merged[merged.count - 1] = TaggedRedactionSpan(span: combinedSpan, tags: last.tags.union([entry.tag]))
            } else {
                merged.append(TaggedRedactionSpan(span: entry.span, tags: [entry.tag]))
            }
        }
        return merged
    }

    /// Inserts a placeholder (rendered by `placeholder`, from each span's
    /// tag set) into `transcript` at each redaction span's position.
    /// `segments` are `transcript`'s OWN word-level timing -- i.e. from
    /// re-transcribing the REDACTED audio, not the original. That's safe
    /// to align by time against spans computed from the original audio's
    /// timing because `redactAudio` mutes samples in place rather than
    /// cutting them out, so a redacted file has the exact same length/
    /// timeline as the source. A span's insertion point is right after the
    /// segment with the latest START time before the span begins (or the
    /// very start of the transcript, if none) -- NOT the latest END time;
    /// confirmed on real hardware that the word immediately preceding a
    /// gap of silence routinely has its reported duration inflated to
    /// cover that trailing silence, pushing its `end` past where the gap
    /// actually starts and causing an end-based search to skip over it
    /// and land the placeholder one word too early. A segment's `timestamp`
    /// (when it starts) isn't subject to that bias -- it's set by when
    /// speech begins, not by how long the recognizer decides to attribute
    /// to it before the next event.
    static func splicePlaceholders<Tag: Hashable>(
        into transcript: String,
        segments: [RecognizedSegment],
        spans: [TaggedRedactionSpan<Tag>],
        placeholder: (Set<Tag>) -> String
    ) -> String {
        guard !spans.isEmpty else { return transcript }

        // Built as trimmed, non-empty pieces joined by a single space --
        // not by concatenating raw substrings with a hand-placed space
        // around each placeholder, which gets the spacing wrong at the
        // very start/end of the transcript (confirmed by a real test
        // failure: a leading redacted span produced a stray leading space
        // and no separator before the following word).
        var pieces: [String] = []
        var cursor = transcript.startIndex
        for taggedSpan in spans.sorted(by: { $0.span.lowerBound < $1.span.lowerBound }) {
            let insertionPoint = segments
                .filter { $0.timestamp < taggedSpan.span.lowerBound }
                .max(by: { $0.timestamp < $1.timestamp })?
                .range.upperBound ?? transcript.startIndex
            guard insertionPoint >= cursor else { continue } // out-of-order/overlapping spans -- skip rather than corrupt the string
            let before = transcript[cursor..<insertionPoint].trimmingCharacters(in: .whitespaces)
            if !before.isEmpty { pieces.append(before) }
            pieces.append(placeholder(taggedSpan.tags))
            cursor = insertionPoint
        }
        let remainder = transcript[cursor...].trimmingCharacters(in: .whitespaces)
        if !remainder.isEmpty { pieces.append(remainder) }
        return pieces.joined(separator: " ")
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
