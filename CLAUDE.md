# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

ReadFlow is a Flutter app (Android + iOS only, package name `readflow`, Android app id `com.doctruyen.readflow`) for reading PDF books as reflowed text and listening to them via text-to-speech. The target content and all user-facing strings are Vietnamese, hardcoded in the widgets (no i18n layer). The README is still the default Flutter template.

## Commands

```bash
flutter pub get                 # install dependencies
flutter run                     # run on a connected device/emulator
flutter analyze                 # lint (flutter_lints; build/, android/, ios/ are excluded)
flutter test                    # run all tests
flutter test test/widget_test.dart --plain-name "Book model"   # run a single test by name
flutter build apk               # Android release build
```

`analysis_options.yaml` sets `deprecated_member_use: ignore`, so deprecated API usage will not show up in `flutter analyze`.

Flutter may not be on `PATH`; the SDK location is in `android/local.properties` (`flutter.sdk`), so call `<flutter.sdk>\bin\flutter.bat` directly if `flutter` is not found.

Tests are pure unit tests: `test/widget_test.dart` (despite its name, only the `Book` and `ReaderSettings` models) and `test/pdf_text_layout_test.dart`. There are no widget tests and nothing that covers the services, which depend on platform plugins (sqflite, flutter_tts, shared_preferences).

## Architecture

Three layers under `lib/`: `models/` (immutable data classes with `copyWith` and `toMap`/`fromMap`), `services/` (singletons), and `ui/` (screens, sheets, dialogs).

**State management** uses no package. Each service is a singleton reached through `X.instance`, and reactive state is exposed as a `ValueNotifier` that the UI consumes through `ValueListenableBuilder`; screen-local state uses `setState`. `SettingsService.instance.init()` is awaited in `main()` before `runApp`.

**Page indexing** is 0-based everywhere (models, database, TTS state) and only converted to 1-based for display and for `pdfx`, whose controller uses 1-based page numbers (see the `+ 1` / `- 1` conversions in `ReaderScreen`).

### PDF pipeline

Two PDF libraries are used for different jobs:

- `syncfusion_flutter_pdf` (in `PdfService`) reads page count, the outline (table of contents), and extracts text.
- `pdfx` (in `OriginalPdfView`, imported as `px`) renders the original pages for `ViewMode.originalPage`. The widget owns its `PdfControllerPinch`, which must only be used while the view is mounted: its `page` getter and `animateToPage` throw when no view is attached or the document has not loaded.

`PdfService.loadPageContent` is the single entry point for page text, used by both the reader UI and TTS. It resolves through three tiers: an in-memory map keyed by book id, then the SQLite `page_cache` table (content stored as a JSON-encoded list of paragraph strings), then `extractPageParagraphs`. Concurrent requests for the same page share one load. A page that fails to extract shows an error paragraph but is not written to `page_cache`.

`PdfService` keeps the most recently used Syncfusion document open (parsing is the expensive step) and reuses it for page count, outline and text extraction. `ReaderScreen.dispose` calls `releaseDocument()` to free it; the whole file is held in memory while a book is open.

Text extraction (`services/pdf_page_extractor.dart` and the pure logic in `services/pdf_text_layout.dart`) reads each page twice, because no single Syncfusion mode is right for every PDF:

- Plain `extractText` must not be used: it emits one fragment per text run, and these PDFs switch font for Vietnamese diacritics, so words come out as `B ọ n h ắ n`.
- `extractText(layoutText: true)` gives correct word spacing for most files, but for some it returns every line with all spaces removed.
- `extractTextLines` gives line and run positions. Vertical positions are reliable; horizontal run positions drift in some files, which puts spaces inside words.

`paragraphsFromPageText` takes the words from the layout text, switches to position-derived text only when the layout text has lost its spaces, and uses line positions (extra line spacing, first-line indent) to find paragraph breaks, falling back to line length and punctuation.

The paragraph is the unit shared across the app: the reader renders one widget per paragraph and TTS speaks and highlights one paragraph at a time. Changing the extraction rules makes rows already in `page_cache` stale: bump the database version and clear the table in `onUpgrade`, as version 2 does.

### Text-to-speech

`TtsService` holds the playback position in `ValueNotifier<TtsState>` (book id, page, paragraph index, play/pause flags). Playback is a chain driven by the `flutter_tts` completion handler: speak a paragraph, then on completion advance to the next paragraph, or to the next page. All page moves go through `_goToPage`, which loads the page through `PdfService`, skips pages with no text, persists progress, and uses `_positionVersion` to discard a load that finishes after the position has changed again.

- Pause is implemented as `stop()` plus the `isPaused` flag, so resume restarts the current paragraph from its beginning.
- The user-facing speed (0.5x to 2.0x) is multiplied by 0.5 before being passed to `flutter_tts`, where 0.5 is normal speed.
- The language is fixed to `vi-VN` (fallback `vi`).
- `ReaderScreen` listens to the TTS state to follow page changes, and `ReaderParagraph` highlights the paragraph being spoken. The player controls exist only on the reader, so `ReaderScreen.dispose` stops TTS.

### Persistence

- `DatabaseHelper` (sqflite, `readflow.db`) has three tables: `books`, `bookmarks`, `page_cache`. The schema is at `version: 2`; version 2 only clears `page_cache`. Any schema change needs a version bump and a step in `_upgradeDB`. Foreign keys declare `ON DELETE CASCADE`, but `PRAGMA foreign_keys` is never enabled, which is why `deleteBook` deletes child rows manually.
- `SettingsService` stores `ReaderSettings` in `shared_preferences`, writing only the fields that changed. Preset colors live on the `ReaderThemePreset` enum itself. Enums (`FontFamilyType`, `ViewMode`, `ReaderThemePreset`) are persisted by index, so reordering or inserting enum values in the middle changes the meaning of saved settings.
- Books reference the PDF by the absolute path returned from `file_picker`; the file is not copied into app storage.

### Reader UI

`ReaderScreen` has three rendering modes selected from `ReaderSettings`: single-page reflow (horizontal swipe plus tap zones on the left and right 22% of the screen), continuous-scroll reflow (one list item per page, loaded lazily), and the original PDF page view. The screen holds the state (current page, loaded pages, bookmarks); the pieces it composes are in `ui/reader/widgets/` (`ReaderTopBar`, `ReaderBottomBar`, `ReaderParagraph`, `OriginalPdfView`). `_loadPage` never calls `setState` synchronously, which is what makes it safe to call from a list `itemBuilder`.
