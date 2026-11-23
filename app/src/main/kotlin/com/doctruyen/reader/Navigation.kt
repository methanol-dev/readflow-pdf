package com.doctruyen.reader

import androidx.compose.runtime.Composable
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation3.runtime.entryProvider
import androidx.navigation3.runtime.rememberNavBackStack
import androidx.navigation3.ui.NavDisplay
import com.doctruyen.reader.ui.library.LibraryScreen
import com.doctruyen.reader.ui.library.LibraryViewModel
import com.doctruyen.reader.ui.reader.ReaderScreen
import com.doctruyen.reader.ui.reader.ReaderViewModel

@Composable
fun MainNavigation() {
    val backStack = rememberNavBackStack(LibraryNavKey)
    val libraryViewModel: LibraryViewModel = viewModel()
    val readerViewModel: ReaderViewModel = viewModel()

    NavDisplay(
        backStack = backStack,
        onBack = { backStack.removeLastOrNull() },
        entryProvider = entryProvider {
            entry<LibraryNavKey> {
                LibraryScreen(
                    viewModel = libraryViewModel,
                    onOpenBook = { bookId ->
                        backStack.add(ReaderNavKey(bookId))
                    }
                )
            }
            entry<ReaderNavKey> { key ->
                androidx.compose.runtime.key(key.bookId) {
                    ReaderScreen(
                        bookId = key.bookId,
                        viewModel = readerViewModel,
                        onBack = {
                            backStack.removeLastOrNull()
                        }
                    )
                }
            }
        }
    )
}
