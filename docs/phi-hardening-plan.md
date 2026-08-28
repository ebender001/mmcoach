# PHI Hardening Plan (phiBranch)

Goal: dictation currently uses server-based `SFSpeechRecognizer` so
`contextualStrings` vocabulary boosting works (see `SpeechRecognitionService.swift`
header) -- which means raw audio, potentially containing a spoken patient/staff
name or a date of service, can reach Apple's speech-recognition servers before
`PHIFilterService` ever sees the resulting text. On-device-only recognition
closes that gap but makes too many medical-terminology errors to be usable.

This plan describes a **record -> redact -> send** pipeline: detect PHI
on-device from a rough transcript, mute exactly those spans in the recorded
audio, and only then send the (already-redacted) file to Apple's server-based
recognizer for the real, jargon-accurate transcript. Only audio already
confirmed not to contain a flagged name/date ever leaves the device.

## Core pipeline (per dictation segment)

1. **Record** -- capture mic audio to a local file (not just streamed to a
   live request), reusing the existing `AVAudioEngine` tap in
   `SpeechRecognitionService`.
2. **Scan (on-device)** -- run `SFSpeechRecognizer` with
   `requiresOnDeviceRecognition = true` against that same audio, over the
   recorded file, **sequentially after the primary (server-based) task has
   already finished** -- not live/concurrently with it. Confirmed
   empirically: this device can't run two `SFSpeechRecognitionTask`s
   against live microphone audio at the same time (every attempt at
   running the scan live in parallel with the primary task failed
   instantly with "No speech detected", regardless of recognizer instance,
   request config, or whether the two tasks shared the same
   `AVAudioPCMBuffer` objects; the identical on-device request succeeded
   immediately once nothing else was actively consuming live audio at the
   same time). Uses `SFSpeechURLRecognitionRequest` against the file step 1
   already wrote, not a second live buffer-fed request -- see step 6, which
   reuses the same file-based pattern. Produces a rough transcript plus
   per-word timestamps (`SFTranscriptionSegment.timestamp`/`.duration`).
   Never touches the network.
3. **Detect** -- run the existing `PHIFilterService` (NLTagger +
   NSDataDetector) over the on-device transcript, producing findings
   (name/institution/date) with character ranges.
4. **Map** -- match each finding's character range back to the
   `SFTranscriptionSegment`(s) it came from, producing a list of
   `[startTime, endTime]` spans in the recording, each padded by roughly
   150-250ms on both sides (timestamps aren't exact, and coarticulation with
   neighboring words can bleed across the edge).
5. **Redact** -- mute those spans in the recorded audio file (zero the PCM
   samples / splice in silence). Everything outside the flagged spans stays
   bit-identical to the original.
6. **Transcribe (server-based)** -- upload the *redacted* file to
   `SFSpeechRecognizer` server-based, with `contextualStrings` set, for the
   real, jargon-accurate transcript. This is the only network audio call in
   the whole pipeline, and it never carries the flagged spans.
7. **Splice** -- align the server transcript's segments to the redaction
   spans by timestamp and insert `"[name removed]"` / `"[date removed]"`
   placeholders at the right positions, rather than trusting the server to
   produce something sensible for a gap of silence.
8. **Re-screen (defense-in-depth)** -- run `PHIFilterService` again on the
   final assembled text (same as today's behavior). Catches anything the
   on-device pass missed (e.g. a name garbled badly enough that it no longer
   reads as a name), and still covers hand-typed text exactly as it does now.
9. **Correct (unchanged)** -- the existing `correctDictation` cloud call runs
   on the redacted+placeholder text, same as today.

## Components

| Component | Change |
| --- | --- |
| `SpeechRecognitionService` | Add file-backed recording alongside the tap; add a `requiresOnDeviceRecognition = true` request path for step 2 |
| **New:** `AudioRedactionService` (name TBD) | Owns steps 4-5: finding-to-segment mapping, padding math, muting samples in an `AVAudioFile`/`AVAudioPCMBuffer`, writing the redacted file |
| `PHIFilterService` | No core logic changes -- reused as-is for steps 3 and 8. May add a variant that returns findings with segment indices, not just character ranges |
| `DictationController` | New phase(s) between `finishingUp` and `correcting` for the scan/redact/re-transcribe work; UI just sees a longer "processing" window, same as today's spinner state |

## Phased build order

Detection quality gets validated *before* anything touches audio:

1. **Capture only** ✅ -- add file-based recording in parallel with the
   existing live stream, no behavior change yet. Confirms the plumbing
   works.
2. **Detect only** ✅ -- run the on-device pass + `PHIFilterService` over
   test recordings, log what *would* be redacted, don't mute anything yet.
   Validated against real speech (correctly caught a name and a date in a
   test phrase, even with unrelated medical-jargon garbling nearby) --
   runs as a sequential pass after the primary task finishes, not live in
   parallel with it (see step 2 above for why).
3. **Redact** ✅ -- `AudioRedactionService`: maps finding ranges to
   word-level timing (padded, merged), mutes those sample ranges in the
   recorded file. Validated with a standalone macOS driver (no mic/device
   needed, per the plan) -- which caught a real bug in the process:
   `AVAudioFile.read(into:)` doesn't reliably fill a buffer to its
   requested capacity in one call, and a naive retry silently loses audio
   rather than appending. Fixed with a chunked read loop; confirmed
   correct (including past the chunk boundary) before this was ever run
   against real hardware. Not yet wired into the live dictation flow.
4. **Re-transcribe** ✅ -- `redactAndReTranscribe` in `SpeechRecognitionService`
   uploads the redacted file (not the original) to the server-based
   recognizer, contextualStrings still active. Validated end-to-end on real
   hardware: the flagged name and date were cleanly absent from the final
   transcript (no hallucinated noise for the silent gaps), and jargon that
   the on-device pass had mangled ("sadness Bain graft") transcribed
   correctly ("saphenous vein graft") once contextualStrings was back in
   play -- confirming the core thesis: real medical-term accuracy with
   PHI-bearing audio never reaching Apple's servers. Still not wired into
   `sessionTranscript` -- this whole pipeline runs as an independent side
   pass alongside the untouched primary flow.
5. **Splice + re-screen** ✅ (standalone-validated; awaiting a real-device
   pass) -- `AudioRedactionService.splicePlaceholders` inserts a
   category-labeled placeholder into the re-transcribed text at each
   redaction span's position, by time-aligning against the re-transcribed
   result's own segments (valid because `redactAudio` mutes samples in
   place, so the redacted file shares the original's exact timeline --
   no fuzzy text matching between the two different transcripts needed).
   `redactionSpans` is now generic over a tag (PHI category), so a merged
   span remembers every category it covered; `PHIFinding.Category.combinedPlaceholder`
   renders "[name removed]" or "[name and date removed]" accordingly. The
   existing text-based `PHIFilterService.redact(_:)` then re-screens the
   spliced result as a defense-in-depth pass. A standalone test caught a
   real spacing bug before it touched real audio -- a redacted span before
   the transcript's first word produced a stray leading space and no
   separator; fixed by building explicit trimmed pieces joined by one
   space rather than hand-placing spaces around substring concatenation.
6. **Retire the old streaming-only path** once the new pipeline is validated
   end-to-end.
7. **Tests** -- unit tests for the finding-to-segment mapping and the
   sample-muting math (pure logic, no real audio needed); manual verification
   passes with scripted test phrases containing fake names/dates, checking
   both that the redacted audio is inaudible in those spans and that
   surrounding medical terms transcribe correctly.

## Known edge cases to explicitly verify in step 7

- Flagged name at the very start/end of a segment (padding running off the
  clip boundary).
- Two flagged spans close enough together that their padding overlaps.
- A name garbled badly enough by the on-device pass that NER misses it
  (confirms step 8's defense-in-depth actually catches it).
- A date phrase spoken unusually (e.g. "postoperative day three" -- should
  *not* fire, it's relative, not absolute).
- **Splice position accuracy across recognizers** (found during step 5's
  real-device validation): the on-device pass and the server re-transcribe
  pass are two independent recognizers processing the identical audio
  file, so their own word-boundary timestamp estimates can disagree by a
  meaningful margin even though the underlying acoustic events happen at
  the same real times. Observed once: a placeholder landed before
  "Patient" instead of after it, because the server pass's own segment for
  "Patient" ended up timed slightly later than the redaction span's start
  (computed from the on-device pass's timing). Not a correctness or
  privacy bug -- nothing leaked, nothing crashed, the redacted content was
  still fully removed and correctly labeled -- but worth a tolerance
  margin in `splicePlaceholders`'s insertion-point search once there's
  more real-phrase data to tune against.
