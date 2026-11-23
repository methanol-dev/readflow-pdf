package com.doctruyen.reader.tts

import android.content.Context
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import com.doctruyen.reader.data.BookRepository
import com.doctruyen.reader.data.model.Book
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.Locale

data class TtsState(
    val isPlaying: Boolean = false,
    val isPaused: Boolean = false,
    val bookId: Long = 0L,
    val currentPage: Int = 0,
    val currentParagraphIndex: Int = 0,
    val totalPages: Int = 0,
    val totalParagraphs: Int = 0,
    val currentParagraphText: String = "",
    val speechRate: Float = 1.0f,
    val isAvailable: Boolean = false,
    val errorMessage: String? = null
)

class TtsManager(
    private val context: Context,
    private val bookRepository: BookRepository
) : TextToSpeech.OnInitListener {

    private val scope = CoroutineScope(Dispatchers.Main + Job())
    private var tts: TextToSpeech? = null

    private val _state = MutableStateFlow(TtsState())
    val state: StateFlow<TtsState> = _state.asStateFlow()

    private var currentBook: Book? = null
    private var currentParagraphs: List<String> = emptyList()

    init {
        tts = TextToSpeech(context.applicationContext, this)
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            val ttsEngine = tts ?: return

            // Prefer Vietnamese, fallback to default locale
            val viLocale = Locale("vi", "VN")
            val result = ttsEngine.setLanguage(viLocale)
            if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
                // Fallback to device's default locale
                ttsEngine.language = Locale.getDefault()
            }

            ttsEngine.setSpeechRate(_state.value.speechRate)

            ttsEngine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {}

                override fun onDone(utteranceId: String?) {
                    scope.launch {
                        handleUtteranceDone()
                    }
                }

                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) {
                    scope.launch {
                        _state.update { it.copy(isPlaying = false, isPaused = false, errorMessage = "Lỗi phát âm thanh TTS") }
                    }
                }
            })

            _state.update { it.copy(isAvailable = true) }
        } else {
            _state.update { it.copy(isAvailable = false, errorMessage = "Không thể khởi tạo Text-to-Speech trên thiết bị") }
        }
    }

    fun startReading(book: Book, startPage: Int = book.lastReadPage, startParagraphIndex: Int = 0) {
        currentBook = book
        val pageClamped = startPage.coerceIn(0, (book.pageCount - 1).coerceAtLeast(0))

        scope.launch {
            loadAndSpeakPage(book, pageClamped, startParagraphIndex)
        }
    }

    private suspend fun loadAndSpeakPage(book: Book, pageIndex: Int, paragraphIndex: Int) {
        val content = bookRepository.getPageContent(book.id, book.filePath, pageIndex)
        currentParagraphs = content.paragraphs

        val safeParagraphIdx = paragraphIndex.coerceIn(0, (currentParagraphs.size - 1).coerceAtLeast(0))

        _state.update {
            it.copy(
                isPlaying = true,
                isPaused = false,
                bookId = book.id,
                currentPage = pageIndex,
                totalPages = book.pageCount,
                currentParagraphIndex = safeParagraphIdx,
                totalParagraphs = currentParagraphs.size,
                currentParagraphText = currentParagraphs.getOrNull(safeParagraphIdx) ?: "",
                errorMessage = null
            )
        }

        // Save progress to database so user never loses their reading spot
        bookRepository.updateProgress(book.id, pageIndex)

        if (currentParagraphs.isEmpty()) {
            // Empty page or scan page: advance to next page automatically
            if (pageIndex + 1 < book.pageCount) {
                loadAndSpeakPage(book, pageIndex + 1, 0)
            } else {
                stop()
            }
            return
        }

        speakCurrentParagraph()
    }

    private fun speakCurrentParagraph() {
        val ttsEngine = tts ?: return
        val currentParagraphIdx = _state.value.currentParagraphIndex
        val textToSpeak = currentParagraphs.getOrNull(currentParagraphIdx)

        if (textToSpeak.isNullOrBlank()) {
            handleUtteranceDone()
            return
        }

        _state.update {
            it.copy(
                isPlaying = true,
                isPaused = false,
                currentParagraphIndex = currentParagraphIdx,
                currentParagraphText = textToSpeak
            )
        }

        val params = Bundle().apply {
            putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, "utterance_${_state.value.currentPage}_$currentParagraphIdx")
        }

        ttsEngine.speak(textToSpeak, TextToSpeech.QUEUE_FLUSH, params, "utterance_${_state.value.currentPage}_$currentParagraphIdx")
    }

    private fun handleUtteranceDone() {
        val book = currentBook ?: return
        val currentState = _state.value
        if (!currentState.isPlaying || currentState.isPaused) return

        val nextParagraphIdx = currentState.currentParagraphIndex + 1

        if (nextParagraphIdx < currentParagraphs.size) {
            // Read next paragraph on same page
            _state.update { it.copy(currentParagraphIndex = nextParagraphIdx) }
            speakCurrentParagraph()
        } else {
            // Reached end of current page: ADVANCE TO NEXT PAGE AUTOMATICALLY!
            val nextPage = currentState.currentPage + 1
            if (nextPage < book.pageCount) {
                scope.launch {
                    loadAndSpeakPage(book, nextPage, 0)
                }
            } else {
                // Reached the end of the entire PDF file!
                stop()
            }
        }
    }

    fun pause() {
        tts?.stop()
        _state.update { it.copy(isPlaying = false, isPaused = true) }
    }

    fun resume() {
        if (_state.value.isPaused && currentBook != null) {
            speakCurrentParagraph()
        }
    }

    fun stop() {
        tts?.stop()
        _state.update {
            it.copy(
                isPlaying = false,
                isPaused = false,
                currentParagraphText = ""
            )
        }
    }

    fun nextParagraph() {
        val book = currentBook ?: return
        tts?.stop()
        val nextParagraphIdx = _state.value.currentParagraphIndex + 1

        if (nextParagraphIdx < currentParagraphs.size) {
            _state.update { it.copy(currentParagraphIndex = nextParagraphIdx) }
            speakCurrentParagraph()
        } else {
            val nextPage = _state.value.currentPage + 1
            if (nextPage < book.pageCount) {
                scope.launch {
                    loadAndSpeakPage(book, nextPage, 0)
                }
            } else {
                stop()
            }
        }
    }

    fun previousParagraph() {
        val book = currentBook ?: return
        tts?.stop()
        val prevParagraphIdx = _state.value.currentParagraphIndex - 1

        if (prevParagraphIdx >= 0) {
            _state.update { it.copy(currentParagraphIndex = prevParagraphIdx) }
            speakCurrentParagraph()
        } else {
            val prevPage = _state.value.currentPage - 1
            if (prevPage >= 0) {
                scope.launch {
                    val prevContent = bookRepository.getPageContent(book.id, book.filePath, prevPage)
                    val lastIdx = (prevContent.paragraphs.size - 1).coerceAtLeast(0)
                    loadAndSpeakPage(book, prevPage, lastIdx)
                }
            } else {
            speakCurrentParagraph()
            }
        }
    }

    fun setSpeechRate(rate: Float) {
        val clamped = rate.coerceIn(0.5f, 2.5f)
        tts?.setSpeechRate(clamped)
        _state.update { it.copy(speechRate = clamped) }
    }

    fun destroy() {
        stop()
        tts?.shutdown()
        tts = null
    }
}
