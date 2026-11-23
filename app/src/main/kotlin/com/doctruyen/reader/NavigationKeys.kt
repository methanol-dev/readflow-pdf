package com.doctruyen.reader

import androidx.navigation3.runtime.NavKey
import kotlinx.serialization.Serializable

@Serializable
data object LibraryNavKey : NavKey

@Serializable
data class ReaderNavKey(val bookId: Long) : NavKey
