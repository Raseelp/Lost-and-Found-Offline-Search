package dev.twentyonevision.app.embedder.storage

import android.content.Context
import android.net.Uri
import java.nio.ByteBuffer
import java.security.MessageDigest

object HashUtils {

    // Cheap dedup key for scan loops - doesn't read file content, so it's
    // fast enough for a whole-device scan. Rolls size + lastModified + name
    // across a full 64-bit space to keep collisions effectively impossible.
    fun identityHash(size: Long, lastModified: Long, name: String): Long {
        var h = 1125899906842597L
        h = 31 * h + size
        h = 31 * h + lastModified
        for (c in name) {
            h = 31 * h + c.code
        }
        return h
    }

    // True content hash (SHA-256), for when reading the whole file is
    // affordable. Not used by the scan loops.
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
