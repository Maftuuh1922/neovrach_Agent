package com.neovarch.agent

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File
import java.io.FileNotFoundException

/**
 * Read-only provider for files the app shares (profile card PNGs): serves
 * `content://<package>.nvshare/<name>` from cache/share/ only, so the share
 * sheet can read them with a temporary grant. No androidx dependency.
 */
class NvShareProvider : ContentProvider() {
    private fun dir(): File = File(context!!.cacheDir, "share")

    private fun fileFor(uri: Uri): File {
        val name = uri.lastPathSegment ?: throw FileNotFoundException("no name")
        val f = File(dir(), name)
        if (f.parentFile?.canonicalPath != dir().canonicalPath || !f.isFile) throw FileNotFoundException(name)
        return f
    }

    override fun onCreate(): Boolean = true

    override fun getType(uri: Uri): String =
        if ((uri.lastPathSegment ?: "").endsWith(".png")) "image/png" else "application/octet-stream"

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor =
        ParcelFileDescriptor.open(fileFor(uri), ParcelFileDescriptor.MODE_READ_ONLY)

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor {
        val f = fileFor(uri)
        val cols = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val c = MatrixCursor(cols)
        c.addRow(cols.map { if (it == OpenableColumns.SIZE) f.length() else if (it == OpenableColumns.DISPLAY_NAME) f.name else null }.toTypedArray())
        return c
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0
}
