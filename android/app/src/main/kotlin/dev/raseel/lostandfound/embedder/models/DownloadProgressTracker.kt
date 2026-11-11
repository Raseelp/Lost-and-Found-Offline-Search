package dev.raseel.lostandfound.embedder.models

/**
 * Turns the byte counts of models that download at the same time into the one stream of progress the app shows. The
 * overall numbers add every model up. The model named in an event is the first one still downloading, so the words on
 * the screen do not jump between files, or the last one being checked when all the bytes are in.
 *
 * Several threads may report, and the events leave in the order they were made.
 */
class DownloadProgressTracker(
    models: List<RemoteModel>,
    private val pending: List<RemoteModel>,
    private val sink: (ModelDownloadProgress) -> Unit,
    private val clock: () -> Long = System::currentTimeMillis,
    private val intervalMs: Long = 250L
) {
    private val total = models.sumOf { it.sizeBytes }
    private val alreadyHere = models.filter { m -> pending.none { it.id == m.id } }.sumOf { it.sizeBytes }
    private val received = HashMap<String, Long>().apply { pending.forEach { put(it.id, 0L) } }
    private val finished = HashSet<String>()
    private var lastEmit = 0L

    /** A block arrived: [bytes] is how many bytes of [model] are in. Reported at most once per interval. */
    @Synchronized
    fun received(model: RemoteModel, bytes: Long) {
        received[model.id] = bytes
        val now = clock()
        if (now - lastEmit <= intervalMs) return
        lastEmit = now
        emit()
    }

    /** Every byte of [model] is in and it is about to be checked. */
    @Synchronized
    fun allBytesReceived(model: RemoteModel) {
        received[model.id] = model.sizeBytes
        emit()
    }

    /** [model] was checked and is in its place. */
    @Synchronized
    fun finished(model: RemoteModel) {
        received[model.id] = model.sizeBytes
        finished.add(model.id)
        emit()
    }

    private fun focus(): RemoteModel =
        pending.firstOrNull { it.id !in finished && (received[it.id] ?: 0L) < it.sizeBytes }
            ?: pending.firstOrNull { it.id !in finished }
            ?: pending.last()

    private fun emit() {
        val model = focus()
        val inNow = alreadyHere + received.values.sum()
        sink(
            ModelDownloadProgress(
                modelId = model.id,
                modelFileName = model.fileName,
                bytesForModel = received[model.id] ?: 0L,
                totalBytesForModel = model.sizeBytes,
                overallBytesDownloaded = minOf(total, inNow),
                overallTotalBytes = total,
                done = model.id in finished
            )
        )
    }
}
