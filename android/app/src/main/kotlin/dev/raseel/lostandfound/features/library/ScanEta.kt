package dev.raseel.lostandfound.features.library

/**
 * The time an indexing scan has left, worked out from what it has really done.
 *
 * Only the files that had to be indexed count: the ones already in the index are skipped in an instant, and counting
 * them as done made a scan that carries on, or a library that is mostly indexed, look as if it would be over in minutes.
 * The time is measured from when the work began, not from when the scan did (the listing of the phone comes first). The
 * speed is the average over the photos so far, and the average over the videos so far, because a video takes many times
 * as long as a photo and the scan does the photos first and the videos after. Before the first videos are done they are
 * counted at the number of photos that a video took in the last scan that timed both, or at [VIDEO_PRIOR] photos each
 * when there is no such scan. The average is over everything done so far, because an estimate that follows every wobble
 * of the speed is more distracting than useful.
 *
 * Times are milliseconds on one clock that the caller chooses. Nothing here reads a clock.
 */
class ScanEta {
    private var started = false
    private var startMs = 0L
    private var toWorkPhotos = 0
    private var toWorkVideos = 0
    private var photosWorked = 0
    private var videosWorked = 0
    private var videoPrior = VIDEO_PRIOR

    /** When the photos were all done, or -1 while they are not. */
    private var photosEndedMs = -1L

    /**
     * The work begins: [photos] and [videos] are the files that are not in the index yet, and [videoPrior] is how many
     * photos a video is counted as until videos have been timed (see [measuredVideoRatio]).
     */
    fun start(nowMs: Long, photos: Int, videos: Int, videoPrior: Double = VIDEO_PRIOR) {
        started = true
        this.videoPrior = videoPrior.coerceIn(MIN_PRIOR, MAX_PRIOR)
        startMs = nowMs
        toWorkPhotos = photos
        toWorkVideos = videos
        photosWorked = 0
        videosWorked = 0
        photosEndedMs = -1L
    }

    /** [total] photos have been worked through so far (indexed, or found unreadable). */
    fun photosDone(total: Int) {
        photosWorked = total
    }

    /** All the photos are over, at [nowMs], and the videos begin. */
    fun photosOver(nowMs: Long) {
        photosEndedMs = nowMs
    }

    /** [total] videos have been worked through so far. */
    fun videosDone(total: Int) {
        videosWorked = total
    }

    /**
     * How many photos' time a video took in this scan, once enough of both have been timed to say; null before. It is
     * kept for the next scan to start from.
     */
    fun measuredVideoRatio(nowMs: Long): Double? {
        if (!started || toWorkPhotos <= 0 || photosWorked < MIN_PHOTOS || videosWorked < MIN_VIDEOS_FOR_RATIO) return null
        if (photosEndedMs < 0) return null
        val photoSpent = photosEndedMs - startMs
        val videoSpent = nowMs - photosEndedMs
        if (photoSpent < MIN_SPENT_MS || videoSpent <= 0) return null
        val ratio = (videoSpent.toDouble() / videosWorked) / (photoSpent.toDouble() / photosWorked)
        return ratio.coerceIn(MIN_PRIOR, MAX_PRIOR)
    }

    /** Milliseconds left at [nowMs], or [UNKNOWN] while there is too little done to say, or nothing is left. */
    fun leftMs(nowMs: Long): Long {
        if (!started) return UNKNOWN
        val photosLeft = (toWorkPhotos - photosWorked).coerceAtLeast(0)
        val videosLeft = (toWorkVideos - videosWorked).coerceAtLeast(0)
        if (photosLeft == 0 && videosLeft == 0) return UNKNOWN

        var msPerPhoto = -1.0
        if (toWorkPhotos > 0) {
            val spent = (if (photosEndedMs >= 0) photosEndedMs else nowMs) - startMs
            if (photosWorked >= MIN_PHOTOS && spent >= MIN_SPENT_MS) msPerPhoto = spent.toDouble() / photosWorked
        }
        if (photosLeft > 0 && msPerPhoto < 0) return UNKNOWN

        var msPerVideo = -1.0
        if (videosLeft > 0) {
            val videosStartMs = if (toWorkPhotos > 0) photosEndedMs else startMs
            if (videosWorked >= MIN_VIDEOS && videosStartMs >= 0) {
                val spent = nowMs - videosStartMs
                if (spent > 0) msPerVideo = spent.toDouble() / videosWorked
            }
            if (msPerVideo < 0 && msPerPhoto > 0) msPerVideo = msPerPhoto * videoPrior
            if (msPerVideo < 0) return UNKNOWN
        }

        val left = photosLeft * msPerPhoto.coerceAtLeast(0.0) + videosLeft * msPerVideo.coerceAtLeast(0.0)
        return left.toLong()
    }

    companion object {
        const val UNKNOWN = -1L

        /** What a scan has to have done before it says anything about the time left. */
        const val MIN_PHOTOS = 10
        const val MIN_VIDEOS = 2
        const val MIN_SPENT_MS = 4000L

        /** How many photos a video is counted as, until videos have been timed in this scan or an earlier one. */
        const val VIDEO_PRIOR = 6.0

        /** The least and the most a remembered or measured ratio may be, so that one odd scan cannot ruin the next. */
        const val MIN_PRIOR = 2.0
        const val MAX_PRIOR = 40.0

        /** How many videos have to be timed before their ratio to photos is worth remembering. */
        const val MIN_VIDEOS_FOR_RATIO = 5
    }
}
