package dev.raseel.lostandfound.embedder.storage

import android.content.Context
import android.net.Uri
import java.nio.ByteBuffer
import java.security.MessageDigest

object HashUtils {

    /**
     * A cheap dedup key for scan loops. It does not read the file content, so it is fast
     * enough for a whole-device scan. It rolls size, lastModified and name across a full 64-bit
     * space to keep collisions effectively impossible.
     */
    fun identityHash(size: Long, lastModified: Long, name: String): Long {
        var h = 1125899906842597L
        h = 31 * h + size
        h = 31 * h + lastModified
        for (c in name) {
            h = 31 * h + c.code
        }
        return h
    }

    /** A true content hash (SHA-256), for when reading the whole file is affordable. The scan loops do not use it. */
    fun hashUriToLong(
        context: Context,
        uri: Uri
    ): Long {
        val digest = MessageDigest.getInstance("SHA-256")

        context.contentResolver.openInputStream(uri)?.use { input ->
            val buffer = ByteArray(8 * 1024)
            var read: Int
            while (input.read(buffer).also { read = it } != -1) {
                digest.update(buffer, 0, read)
            }
        } ?: return 0L

        val hashBytes = digest.digest()
        return ByteBuffer.wrap(hashBytes, 0, 8).long
    }
}
