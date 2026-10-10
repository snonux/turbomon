package org.buetow.turbomon

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File
import java.io.FileNotFoundException

/**
 * Serves saved snapshots (the .md files in files/snapshots) read-only to the app the
 * user shares them with. A minimal stand-in for androidx FileProvider, so
 * the app needs no extra library.
 */
class SnapshotProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    private fun fileFor(uri: Uri): File {
        val ctx = context ?: throw FileNotFoundException()
        val name = uri.lastPathSegment ?: throw FileNotFoundException()
        val dir = File(ctx.filesDir, "snapshots").canonicalFile
        val f = File(dir, name).canonicalFile
        // No path tricks: only direct children of the snapshots directory.
        if (f.parentFile != dir || !f.isFile) throw FileNotFoundException(name)
        return f
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw SecurityException("read-only")
        return ParcelFileDescriptor.open(fileFor(uri), ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor {
        val f = fileFor(uri)
        val cols = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val row = cols.map { if (it == OpenableColumns.SIZE) f.length() else if (it == OpenableColumns.DISPLAY_NAME) f.name else null }
        return MatrixCursor(cols, 1).apply { addRow(row) }
    }

    override fun getType(uri: Uri): String = "text/markdown"

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0

    companion object {
        fun uriFor(context: Context, file: File): Uri =
            Uri.Builder()
                .scheme("content")
                .authority("${context.packageName}.snapshots")
                .appendPath(file.name)
                .build()
    }
}
