package com.doctruyen.reader.pdf

object TextNormalizer {

    private val PAGE_NUMBER_REGEX = Regex("""^\s*[-–—]?\s*\d+\s*[-–—]?\s*$""")
    private val HYPHENATED_LINE_REGEX = Regex("""(\p{L}+)-\s*\n\s*(\p{L}+)""")
    private val MULTIPLE_SPACES_REGEX = Regex("""[ \t\xA0]+""")
    private val MULTIPLE_NEWLINES_REGEX = Regex("""\n{3,}""")

    fun normalize(rawText: String): List<String> {
        if (rawText.isBlank()) return emptyList()

        // 1. Replace special non-breaking spaces with standard space
        var text = rawText.replace('\u00A0', ' ')
            .replace('\r', '\n')
            .replace(MULTIPLE_NEWLINES_REGEX, "\n\n")

        // 2. Remove hyphenation across line breaks: e.g. "xây-\ndựng" -> "xâydựng"
        text = HYPHENATED_LINE_REGEX.replace(text) { matchResult ->
            val first = matchResult.groupValues[1]
            val second = matchResult.groupValues[2]
            "$first$second"
        }

        // 3. Split by lines and remove page number artifacts
        val rawLines = text.lines()
        val cleanedLines = mutableListOf<String>()

        for (line in rawLines) {
            val trimmed = line.trim()
            if (trimmed.isEmpty()) {
                cleanedLines.add("")
                continue
            }
            // Skip isolated page numbers (e.g., "- 45 -" or "45")
            if (PAGE_NUMBER_REGEX.matches(trimmed)) {
                continue
            }
            cleanedLines.add(trimmed)
        }

        // 4. Group lines into coherent paragraphs
        val paragraphs = mutableListOf<String>()
        val currentParagraph = StringBuilder()

        for (i in cleanedLines.indices) {
            val line = cleanedLines[i]

            if (line.isEmpty()) {
                if (currentParagraph.isNotEmpty()) {
                    paragraphs.add(currentParagraph.toString().trim())
                    currentParagraph.clear()
                }
                continue
            }

            if (currentParagraph.isEmpty()) {
                currentParagraph.append(line)
            } else {
                val prevText = currentParagraph.toString()
                val prevLastChar = prevText.lastOrNull() ?: ' '

                // Check if previous line ended a sentence
                val endsSentence = prevLastChar in listOf('.', '!', '?', '…', ':', '”', '"', ')')
                val isShortLine = line.length < 25 && endsSentence

                if (endsSentence && isShortLine) {
                    // Previous line was likely the end of a paragraph
                    paragraphs.add(currentParagraph.toString().trim())
                    currentParagraph.clear()
                    currentParagraph.append(line)
                } else {
                    // Line continuation: join with single space
                    currentParagraph.append(" ").append(line)
                }
            }
        }

        if (currentParagraph.isNotEmpty()) {
            paragraphs.add(currentParagraph.toString().trim())
        }

        // 5. Clean up each paragraph (no multiple spaces)
        return paragraphs.map { MULTIPLE_SPACES_REGEX.replace(it, " ").trim() }
            .filter { it.isNotEmpty() }
    }
}
