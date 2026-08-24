package dev.benderapps.mmcoach.models

/** Result of BackendService.correctDictation, mirroring mmCorrectDictation's response shape. */
data class CorrectedDictationSegment(
    val correctedSegment: String,
    val changes: List<Change>,
) {
    data class Change(
        val original: String,
        val corrected: String,
    )
}
