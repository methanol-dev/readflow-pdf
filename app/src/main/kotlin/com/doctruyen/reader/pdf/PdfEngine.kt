package com.doctruyen.reader.pdf

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.pdf.PdfDocument
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import com.doctruyen.reader.data.model.PdfPageContent
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.interactive.documentnavigation.outline.PDOutlineItem
import com.tom_roush.pdfbox.text.PDFTextStripper
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream

object PdfEngine {

    private var isInitialized = false

    fun init(context: Context) {
        if (!isInitialized) {
            PDFBoxResourceLoader.init(context.applicationContext)
            isInitialized = true
        }
    }

    data class ImportedPdfResult(
        val title: String,
        val filePath: String,
        val pageCount: Int,
        val coverPath: String?,
        val fileSize: Long
    )

    suspend fun importPdf(context: Context, uri: Uri): ImportedPdfResult = withContext(Dispatchers.IO) {
        init(context)

        // 1. Get original filename
        var fileName = "Document_${System.currentTimeMillis()}.pdf"
        var fileSize = 0L
        context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (nameIndex != -1) {
                    val name = cursor.getString(nameIndex)
                    if (!name.isNullOrBlank()) fileName = name
                }
                if (sizeIndex != -1) {
                    fileSize = cursor.getLong(sizeIndex)
                }
            }
        }

        // 2. Copy file to internal app storage for reliable offline access
        val booksDir = File(context.filesDir, "books").apply { mkdirs() }
        val safeFileName = "${System.currentTimeMillis()}_${fileName.replace("[^a-zA-Z0-9._-]".toRegex(), "_")}"
        val destFile = File(booksDir, safeFileName)

        context.contentResolver.openInputStream(uri)?.use { input ->
            FileOutputStream(destFile).use { output ->
                input.copyTo(output)
            }
        } ?: throw IllegalStateException("Không thể đọc file PDF từ bộ nhớ")

        if (fileSize == 0L) {
            fileSize = destFile.length()
        }

        // 3. Inspect document metadata and page count
        var docTitle = fileName.removeSuffix(".pdf").removeSuffix(".PDF")
        var pageCount = 1

        try {
            PDDocument.load(destFile).use { pdDoc ->
                pageCount = pdDoc.numberOfPages.coerceAtLeast(1)
                val infoTitle = pdDoc.documentInformation?.title
                if (!infoTitle.isNullOrBlank()) {
                    docTitle = infoTitle.trim()
                }
            }
        } catch (e: Exception) {
            // Fallback using native PdfRenderer to read page count if PDFBox hits edge case
            try {
                ParcelFileDescriptor.open(destFile, ParcelFileDescriptor.MODE_READ_ONLY).use { pfd ->
                    PdfRenderer(pfd).use { renderer ->
                        pageCount = renderer.pageCount.coerceAtLeast(1)
                    }
                }
            } catch (ignored: Exception) {}
        }

        // 4. Generate cover thumbnail of first page
        val coversDir = File(context.filesDir, "covers").apply { mkdirs() }
        val coverFile = File(coversDir, "${destFile.nameWithoutExtension}_cover.jpg")
        val coverPath = try {
            generateCoverThumbnail(destFile, coverFile)
            if (coverFile.exists() && coverFile.length() > 0) coverFile.absolutePath else null
        } catch (e: Exception) {
            null
        }

        ImportedPdfResult(
            title = docTitle,
            filePath = destFile.absolutePath,
            pageCount = pageCount,
            coverPath = coverPath,
            fileSize = fileSize
        )
    }

    private fun generateCoverThumbnail(pdfFile: File, outputFile: File) {
        ParcelFileDescriptor.open(pdfFile, ParcelFileDescriptor.MODE_READ_ONLY).use { pfd ->
            PdfRenderer(pfd).use { renderer ->
                if (renderer.pageCount > 0) {
                    renderer.openPage(0).use { page ->
                        val targetWidth = 360
                        val targetHeight = ((targetWidth.toFloat() / page.width.toFloat()) * page.height).toInt().coerceAtLeast(480)
                        val bitmap = Bitmap.createBitmap(targetWidth, targetHeight, Bitmap.Config.ARGB_8888)
                        val canvas = Canvas(bitmap)
                        canvas.drawColor(Color.WHITE)
                        page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)

                        FileOutputStream(outputFile).use { out ->
                            bitmap.compress(Bitmap.CompressFormat.JPEG, 85, out)
                        }
                        bitmap.recycle()
                    }
                }
            }
        }
    }

    suspend fun getPageContent(context: Context, filePath: String, pageIndex: Int): PdfPageContent =
        withContext(Dispatchers.IO) {
            init(context)
            val file = File(filePath)
            if (!file.exists()) {
                return@withContext PdfPageContent(pageIndex, emptyList(), "")
            }

            try {
                PDDocument.load(file).use { doc ->
                    if (pageIndex < 0 || pageIndex >= doc.numberOfPages) {
                        return@withContext PdfPageContent(pageIndex, emptyList(), "")
                    }

                    val stripper = PDFTextStripper()
                    stripper.startPage = pageIndex + 1
                    stripper.endPage = pageIndex + 1
                    val rawText = stripper.getText(doc) ?: ""
                    val paragraphs = TextNormalizer.normalize(rawText)

                    PdfPageContent(
                        pageIndex = pageIndex,
                        paragraphs = paragraphs,
                        rawText = rawText
                    )
                }
            } catch (e: Exception) {
                PdfPageContent(
                    pageIndex = pageIndex,
                    paragraphs = listOf("Không thể trích xuất văn bản từ trang ${pageIndex + 1}: ${e.localizedMessage ?: "Lỗi định dạng PDF"}"),
                    rawText = ""
                )
            }
        }

    suspend fun renderPageBitmap(
        filePath: String,
        pageIndex: Int,
        targetWidth: Int
    ): Bitmap? = withContext(Dispatchers.IO) {
        val file = File(filePath)
        if (!file.exists()) return@withContext null

        try {
            ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { pfd ->
                PdfRenderer(pfd).use { renderer ->
                    if (pageIndex < 0 || pageIndex >= renderer.pageCount) return@withContext null

                    renderer.openPage(pageIndex).use { page ->
                        val scale = targetWidth.toFloat() / page.width.toFloat()
                        val targetHeight = (page.height * scale).toInt().coerceAtLeast(100)

                        val bitmap = Bitmap.createBitmap(targetWidth, targetHeight, Bitmap.Config.ARGB_8888)
                        val canvas = Canvas(bitmap)
                        canvas.drawColor(Color.WHITE)
                        page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                        bitmap
                    }
                }
            }
        } catch (e: Exception) {
            null
        }
    }

    suspend fun extractOutline(context: Context, filePath: String): List<Pair<String, Int>> = withContext(Dispatchers.IO) {
        init(context)
        val result = mutableListOf<Pair<String, Int>>()
        val file = File(filePath)
        if (!file.exists()) return@withContext result

        try {
            PDDocument.load(file).use { doc ->
                val outline = doc.documentCatalog.documentOutline ?: return@withContext result
                var current: PDOutlineItem? = outline.firstChild
                while (current != null) {
                    val title = current.title
                    val page = current.findDestinationPage(doc)
                    if (title != null && page != null) {
                        val pageIndex = doc.pages.indexOf(page)
                        if (pageIndex >= 0) {
                            result.add(Pair(title.trim(), pageIndex))
                        }
                    }
                    current = current.nextSibling
                }
            }
        } catch (ignored: Exception) {}

        result
    }

    // Creates a sample story PDF if the user wants to test immediately
    suspend fun createSampleStoryPdf(context: Context): File = withContext(Dispatchers.IO) {
        val booksDir = File(context.filesDir, "books").apply { mkdirs() }
        val sampleFile = File(booksDir, "truyen_mau_de_men.pdf")
        if (sampleFile.exists()) return@withContext sampleFile

        val doc = PdfDocument()
        val paint = Paint().apply {
            textSize = 14f
            color = Color.BLACK
            isAntiAlias = true
        }
        val titlePaint = Paint().apply {
            textSize = 20f
            color = Color.BLACK
            isFakeBoldText = true
            isAntiAlias = true
        }

        val chapters = listOf(
            Pair("Chương 1: Bài Học Đường Đời Đầu Tiên", listOf(
                "Tôi sống độc lập từ thuở bé. Ấy là tục lệ lâu đời trong họ dế chúng tôi. Vả lại, mẹ thường bảo chúng tôi rằng: 'Phải tự lập thân từ thuở nhỏ thì sau này mới nên người.'",
                "Cứ về mùa thu, khi mưa dầm dề ngớt hẳn, gió heo may se lạnh thổi về, mẹ tôi lại dẫn chúng tôi ra mé bờ ruộng, chia cho mỗi đứa một hang đất nhỏ rồi dặn dò quay về.",
                "Thế là từ đấy tôi bắt đầu một cuộc đời tự lập. Tôi đào hang sâu vào trong lòng đất, có nhiều ngóc ngách, cửa trước cửa sau thông nhau để phòng khi bất trắc.",
                "Tôi ăn uống điều độ và làm việc có chừng mực nên tôi chóng lớn lắm. Chẳng bao lâu tôi đã trở thành một chàng dế thanh niên cường tráng. Đôi càng tôi mẫm bóng, vuốt ở chân cứ cứng dần và nhọn hoắt.",
                "Thỉnh thoảng, muốn thử sự lợi hại của những chiếc vuốt, tôi co cẳng lên, đạp phanh phách vào các ngọn cỏ. Những ngọn cỏ gãy rạp, y như có nhát dao vừa lia qua."
            )),
            Pair("Chương 2: Cuộc Du Hành Ra Thế Giới Lớn", listOf(
                "Đứng mãi trong một góc hang tối tăm chật hẹp, tôi thấy ngột ngạt và buồn chán quá. Cảnh vật ngoài kia rộng lớn mênh mông, biết bao điều kỳ thú đang chờ đón.",
                "Tôi quyết định khăn gói lên đường chu du thiên hạ. Bạn Xiến Tóc bảo tôi: 'Đi một ngày đàng, học một sàng khôn. Tuổi trẻ không xông pha thì khi về già lấy gì mà nhớ?'",
                "Men theo con mương nhỏ, tôi gặp những bãi cỏ xanh ngát đọng sương mai lấp lánh như những hạt ngọc trời. Tiếng chim hót rộn ràng trên những tán lá râm bụt.",
                "Mỗi bước chân đi là một phát hiện mới lạ. Đời đẹp biết bao khi ta mang trong mình ước mơ bay xa và một trái tim can đảm!"
            ))
        )

        for ((index, chapter) in chapters.withIndex()) {
            val pageInfo = PdfDocument.PageInfo.Builder(595, 842, index + 1).create()
            val page = doc.startPage(pageInfo)
            val canvas = page.canvas

            var y = 80f
            canvas.drawText(chapter.first, 50f, y, titlePaint)
            y += 40f

            for (paragraph in chapter.second) {
                // simple word wrap for sample generator
                val words = paragraph.split(" ")
                var line = ""
                for (word in words) {
                    if (paint.measureText("$line $word") < 490f) {
                        line = if (line.isEmpty()) word else "$line $word"
                    } else {
                        canvas.drawText(line, 50f, y, paint)
                        y += 24f
                        line = word
                    }
                }
                if (line.isNotEmpty()) {
                    canvas.drawText(line, 50f, y, paint)
                    y += 34f
                }
            }

            doc.finishPage(page)
        }

        FileOutputStream(sampleFile).use { out ->
            doc.writeTo(out)
        }
        doc.close()

        sampleFile
    }
}
