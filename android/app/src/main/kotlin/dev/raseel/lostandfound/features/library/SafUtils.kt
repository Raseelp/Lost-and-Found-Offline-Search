package dev.raseel.lostandfound.features.library

import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.provider.DocumentsContract
import android.util.Log
import java.util.concurrent.Callable
import java.util.concurrent.ExecutorCompletionService
import java.util.concurrent.Executors

/**
 * A document found under a picked SAF folder tree, resolved from the cursor row that found it (see
 * [SafUtils.listOneDirectory]).
 * It is not a DocumentFile on purpose. DocumentFile.listFiles() fetches only the child ids, so each later read of a
 * name or length is its own query to the provider.
 */
data class SafDocument(
    val uri: Uri,
    val name: String,
    val mimeType: String,
    val size: Long,
    val lastModified: Long
)

object SafUtils {

    private const val TAG = "SafUtils"

    /** The directory listing waits on the document provider, not the CPU, so many threads help. */
    private const val TRAVERSE_THREAD_COUNT = 12

    private val PROJECTION = arrayOf(
        DocumentsContract.Document.COLUMN_DOCUMENT_ID,
        DocumentsContract.Document.COLUMN_DISPLAY_NAME,
        DocumentsContract.Document.COLUMN_MIME_TYPE,
        DocumentsContract.Document.COLUMN_SIZE,
        DocumentsContract.Document.COLUMN_LAST_MODIFIED
    )

    fun listImageFiles(
        context: Context,
        treeUri: Uri,
        isCancelled: () -> Boolean = { false },
        onFileFound: () -> Unit = {}
    ): List<SafDocument> = traverse(
        context, treeUri,
        matches = { name, _ -> isImageName(name) },
        isCancelled = isCancelled,
        onFileFound = onFileFound
    )

    fun listVideoFiles(
        context: Context,
        treeUri: Uri,
        isCancelled: () -> Boolean = { false },
        onFileFound: () -> Unit = {}
    ): List<SafDocument> = traverse(
        context, treeUri,
        matches = { _, mimeType -> mimeType.startsWith("video/") },
        isCancelled = isCancelled,
        onFileFound = onFileFound
    )

    private fun isImageName(name: String): Boolean {
        val lower = name.lowercase()
        return lower.endsWith(".jpg") || lower.endsWith(".jpeg") ||
            lower.endsWith(".png") || lower.endsWith(".webp")
    }

    /**
     * Lists the matching documents under [treeUri], reporting each one through [onFileFound] as soon as its directory
     * has been read.
     * Work is driven by completion order, not level by level, which made progress stall and then jump. Only this
     * calling thread waits, because a worker waiting on another could deadlock the pool.
     */
    private fun traverse(
        context: Context,
        treeUri: Uri,
        matches: (name: String, mimeType: String) -> Boolean,
        isCancelled: () -> Boolean,
        onFileFound: () -> Unit
    ): List<SafDocument> {
        val rootDocId = try {
            DocumentsContract.getTreeDocumentId(treeUri)
        } catch (e: Exception) {
            Log.w(TAG, "traverse: couldn't resolve tree document id: ${e.message}")
            return emptyList()
        }

        val results = mutableListOf<SafDocument>()
        val pool = Executors.newFixedThreadPool(TRAVERSE_THREAD_COUNT)
        val completionService = ExecutorCompletionService<Pair<List<SafDocument>, List<String>>>(pool)

        fun submit(docId: String) {
            completionService.submit(Callable { listOneDirectory(context, treeUri, docId, matches) })
        }

        try {
            var pending = 1
            submit(rootDocId)

            while (pending > 0 && !isCancelled()) {
                val future = try {
                    completionService.take()
                } catch (e: InterruptedException) {
                    Thread.currentThread().interrupt()
                    break
                }
                pending--

                val (files, subdirIds) = try {
                    future.get()
                } catch (e: Exception) {
                    Log.w(TAG, "traverse: a directory failed to list: ${e.message}")
                    continue
                }

                for (file in files) {
                    results.add(file)
                    onFileFound()
                }

                if (!isCancelled()) {
                    for (docId in subdirIds) {
                        pending++
                        submit(docId)
                    }
                }
            }
        } finally {
            pool.shutdownNow()
        }

        return results
    }

    /**
     * Lists one directory and tries once more if the first query fails. A momentary provider error, such as a timeout or
     * a busy binder queue, should not cost a whole subtree. A repeated failure, such as revoked access or a removed
     * directory, gives up with an empty result.
     */
    private fun listOneDirectory(
        context: Context,
        treeUri: Uri,
        parentDocId: String,
        matches: (name: String, mimeType: String) -> Boolean
    ): Pair<List<SafDocument>, List<String>> {
        queryOneDirectory(context, treeUri, parentDocId, matches)?.let { return it }

        try {
            Thread.sleep(50)
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
            return emptyList<SafDocument>() to emptyList()
        }

        queryOneDirectory(context, treeUri, parentDocId, matches)?.let { return it }

        Log.w(TAG, "listOneDirectory: giving up on $parentDocId after a retry")
        return emptyList<SafDocument>() to emptyList()
    }

    /**
     * Returns the files and subdirectory ids of one directory. Null means the query failed, which is different from an
     * empty directory. [listOneDirectory] retries only on null.
     */
    private fun queryOneDirectory(
        context: Context,
        treeUri: Uri,
        parentDocId: String,
        matches: (name: String, mimeType: String) -> Boolean
    ): Pair<List<SafDocument>, List<String>>? {
        val files = mutableListOf<SafDocument>()
        val subdirIds = mutableListOf<String>()

        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentDocId)
        var cursor: Cursor? = null
        try {
            cursor = context.contentResolver.query(childrenUri, PROJECTION, null, null, null)
            cursor?.let { c ->
                val idCol = c.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                val nameCol = c.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                val mimeCol = c.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)
                val sizeCol = c.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
                val modCol = c.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)

                while (c.moveToNext()) {
                    val docId = (if (idCol >= 0) c.getString(idCol) else null) ?: continue
                    val name = (if (nameCol >= 0) c.getString(nameCol) else null) ?: ""
                    val mimeType = (if (mimeCol >= 0) c.getString(mimeCol) else null) ?: ""
                    val size = if (sizeCol >= 0) c.getLong(sizeCol) else 0L
                    val lastModified = if (modCol >= 0) c.getLong(modCol) else 0L

                    if (mimeType == DocumentsContract.Document.MIME_TYPE_DIR) {
                        subdirIds.add(docId)
                    } else if (matches(name, mimeType)) {
                        val uri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
                        files.add(SafDocument(uri, name, mimeType, size, lastModified))
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "queryOneDirectory: query failed for $parentDocId: ${e.message}")
            return null
        } finally {
            try { cursor?.close() } catch (_: Exception) {}
        }

        return files to subdirIds
    }
}
