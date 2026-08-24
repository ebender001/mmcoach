package dev.benderapps.mmcoach.models

/** One labeled piece of a PubMed abstract (e.g. "Background", "Methods"). */
data class PubMedAbstractSection(
    val label: String?,
    val text: String,
)

/**
 * One PubMed article returned by mmFindReferences. Distinct from
 * [ReferenceItem], which is the AI-identified *topic* stored on the case.
 */
data class PubMedReference(
    val pmid: String,
    val title: String,
    val authors: List<String>,
    val journal: String?,
    val year: String?,
    val abstractSections: List<PubMedAbstractSection>,
    val url: String,
) {
    /** "Smith J, Doe A, et al." -- trimmed to a readable byline. */
    val authorByline: String?
        get() {
            if (authors.isEmpty()) return null
            val shown = authors.take(3).joinToString(", ")
            return if (authors.size > 3) "$shown, et al." else shown
        }

    val journalYearLine: String?
        get() = when {
            journal != null && year != null -> "$journal · $year"
            journal != null -> journal
            year != null -> year
            else -> null
        }
}

data class PubMedReferenceSearch(
    val topic: String,
    val results: List<PubMedReference>,
)
