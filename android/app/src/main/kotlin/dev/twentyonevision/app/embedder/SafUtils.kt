package dev.twentyonevision.app.embedder


import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile

object SafUtils {

    // isCancelled is checked between every directory so "Stop scan" works
    // even mid-traversal (a folder like "Android" can take a while to walk).
    // onFileFound fires per match so the caller can show live progress.
    fun listImageFiles(
        context: Context,
        treeUri: Uri,
        isCancelled: () -> Boolean = { false },
        onFileFound: () -> Unit = {}
    ): List<DocumentFile> {

        val root = DocumentFile.fromTreeUri(context, treeUri)
            ?: return emptyList()

        val result = mutableListOf<DocumentFile>()
        traverse(root, result, isCancelled, onFileFound)
        return result
    }

    private fun traverse(
        dir: DocumentFile,
        out: MutableList<DocumentFile>,
        isCancelled: () -> Boolean,
        onFileFound: () -> Unit
    ) {
        if (isCancelled()) return

        for (file in dir.listFiles()) {
            if (isCancelled()) return

            if (file.isDirectory) {
                traverse(file, out, isCancelled, onFileFound)
            } else if (isImage(file)) {
                out.add(file)
                onFileFound()
            }
        }
    }

    private fun isImage(file: DocumentFile): Boolean {
        val name = file.name?.lowercase() ?: return false
        return name.endsWith(".jpg")
                || name.endsWith(".jpeg")
                || name.endsWith(".png")
                || name.endsWith(".webp")
    }

    fun listVideoFiles(
        context: Context,
        folderUri: Uri,
        isCancelled: () -> Boolean = { false },
        onFileFound: () -> Unit = {}
    ): List<DocumentFile> {
        val folder = DocumentFile.fromTreeUri(context, folderUri) ?: return emptyList()
        val results = mutableListOf<DocumentFile>()
        collectVideoFiles(folder, results, isCancelled, onFileFound)
        return results
    }

    private fun collectVideoFiles(
        folder: DocumentFile,
        results: MutableList<DocumentFile>,
        isCancelled: () -> Boolean,
        onFileFound: () -> Unit
    ) {
        if (isCancelled()) return

        for (file in folder.listFiles()) {
            if (isCancelled()) return

            if (file.isDirectory) {
                collectVideoFiles(file, results, isCancelled, onFileFound)
            } else if (file.type?.startsWith("video/") == true) {
                results.add(file)
                onFileFound()
            }
        }
    }
}
