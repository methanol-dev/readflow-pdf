import 'package:flutter/material.dart';
import '../../../models/reader_settings.dart';
import '../../../services/tts_service.dart';

/// One reflowed paragraph, highlighted while TTS is speaking it.
class ReaderParagraph extends StatelessWidget {
  final String text;
  final int? bookId;
  final int pageIndex;
  final int paragraphIndex;
  final ReaderSettings settings;

  const ReaderParagraph({
    super.key,
    required this.text,
    required this.bookId,
    required this.pageIndex,
    required this.paragraphIndex,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TtsState>(
      valueListenable: TtsService.instance.state,
      builder: (context, tts, _) {
        final isSpeaking = tts.isActive &&
            tts.bookId == bookId &&
            tts.currentPage == pageIndex &&
            tts.currentParagraphIndex == paragraphIndex;
        final primary = Theme.of(context).colorScheme.primary;

        return Container(
          margin: EdgeInsets.only(bottom: settings.fontSize * 0.7),
          padding: isSpeaking
              ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
              : EdgeInsets.zero,
          decoration: isSpeaking
              ? BoxDecoration(
                  color: primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                )
              : null,
          child: Text(
            text,
            textAlign: settings.isJustified ? TextAlign.justify : TextAlign.start,
            style: TextStyle(
              color: isSpeaking ? primary : settings.textColor,
              fontSize: settings.fontSize,
              height: settings.lineHeightMultiplier,
              fontFamily: settings.fontFamilyName,
              fontWeight: isSpeaking ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        );
      },
    );
  }
}
