package dev.raseel.lostandfound.core.native

import java.util.concurrent.Executors

/**
 * The threads the native calls run on, one pool per kind of work so that a slow call never holds up an unrelated one.
 * They live for the whole process, shared by all the channels.
 */
object NativeExecutors {
    /**
     * Kept apart from ScanEngineHolder on purpose. Sharing this thread between a running scan and quick
     * queries like areModelsReady made those queries hang behind the scan (see ScanEngineHolder).
     */
    val executor = Executors.newSingleThreadExecutor()

    /**
     * Downloads get their own thread so a long-running download never blocks
     * unrelated calls (e.g. loading an already-cached thumbnail) sitting
     * behind it on the shared executor.
     */
    val downloadExecutor = Executors.newSingleThreadExecutor()

    /**
     * Search gets its own thread so it does not queue behind a scan that can run for an hour or more. EmbeddingEngine
     * and EmbeddingStore allow this with locks around the shared vision module and the on-disk store.
     */
    val searchExecutor = Executors.newSingleThreadExecutor()

    /**
     * Grid thumbnails only: a few in parallel so a collection's tiles fill in
     * together, and off searchExecutor so they never queue behind a search.
     */
    val thumbnailExecutor = Executors.newFixedThreadPool(3)

    /**
     * Face pictures get their own threads: a grid of photo thumbnails filling in
     * (or a search) must never make an avatar wait, and the other way round.
     */
    val faceCropExecutor = Executors.newFixedThreadPool(3)

    /** Work for the zip export that is quick but not instant (reading file sizes and dates). */
    val exportExecutor = Executors.newSingleThreadExecutor()

    /**
     * Face detection has its own thread and detector, with its own ONNX session, so it never waits behind or holds up
     * search or a scan.
     */
    val faceExecutor = Executors.newSingleThreadExecutor()

    /**
     * The memories (dates of everything indexed, "on this day", "then and now") have their own thread,
     * so reading dates never holds up the face calls or a search.
     */
    val memoryExecutor = Executors.newSingleThreadExecutor()

    val logExecutor = Executors.newSingleThreadExecutor()

    /**
     * A photo opened in the viewer that the face scan hasn't reached yet is analysed on
     * its own thread, so it doesn't queue behind the other face calls.
     */
    val photoFacesExecutor = Executors.newSingleThreadExecutor()

    /**
     * A whole video is scanned on its own thread too: it can take a while, and must not hold up
     * the quick look-ups (a photo's faces, the paused frame of a video).
     */
    val videoScanExecutor = Executors.newSingleThreadExecutor()
}
