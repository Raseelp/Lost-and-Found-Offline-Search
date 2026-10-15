package dev.raseel.lostandfound.embedder.faces

import java.util.Calendar
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MediaDatesTest {
    private val now = ms(2026, 10, 13)

    private fun ms(year: Int, month: Int, day: Int, hour: Int = 12): Long {
        val cal = Calendar.getInstance()
        cal.clear()
        cal.set(year, month - 1, day, hour, 0, 0)
        return cal.timeInMillis
    }

    @Test
    fun takenDateWinsWhenItIsReal() {
        val found = MediaDates.pick(
            taken = ms(2019, 8, 12), exif = ms(2018, 1, 1), named = ms(2017, 1, 1),
            modified = ms(2024, 5, 5), added = ms(2024, 5, 6), now = now,
        )
        assertEquals(MediaDates.SRC_TAKEN, found.src)
        assertEquals(ms(2019, 8, 12), found.ms)
    }

    @Test
    fun aCameraWithNoClockIsNotBelieved() {
        // 1970, 2000-01-01 and tomorrow-and-later are skipped, down to the next kind of date.
        val found = MediaDates.pick(
            taken = 0L, exif = ms(2000, 1, 1, 0), named = 0L,
            modified = ms(2021, 3, 4), added = 0L, now = now,
        )
        assertEquals(MediaDates.SRC_MODIFIED, found.src)
        assertEquals(ms(2021, 3, 4), found.ms)

        val future = MediaDates.pick(
            taken = ms(2031, 1, 1), exif = 0L, named = 0L, modified = 0L, added = 0L, now = now,
        )
        assertEquals(MediaDates.SRC_NONE, future.src)
        assertEquals(0L, future.ms)
    }

    @Test
    fun nothingKnownGivesNoDate() {
        val found = MediaDates.pick(0, 0, 0, 0, 0, now)
        assertEquals(MediaDates.SRC_NONE, found.src)
        assertEquals(0L, found.ms)
    }

    @Test
    fun exifComesBeforeTheNameAndTheChangeDate() {
        val found = MediaDates.pick(
            taken = 0L, exif = ms(2015, 6, 7, 9), named = ms(2016, 1, 1),
            modified = ms(2024, 1, 1), added = 0L, now = now,
        )
        assertEquals(MediaDates.SRC_EXIF, found.src)
    }

    @Test
    fun theDayTodayAndTheDayAfterAreStillReal() {
        assertTrue(MediaDates.valid(now, now))
        assertTrue(MediaDates.valid(now + 3_600_000L, now))
        assertFalse(MediaDates.valid(now + 3 * 86_400_000L, now))
        assertFalse(MediaDates.valid(ms(1989, 12, 31), now))
        assertTrue(MediaDates.valid(ms(1990, 1, 2), now))
    }

    @Test
    fun datesInFileNames() {
        assertEquals(ms(2019, 8, 12), MediaDates.dateFromName("IMG-20190812-WA0001.jpg"))
        assertEquals(ms(2021, 1, 1), MediaDates.dateFromName("PXL_20210101_101500123.jpg"))
        assertEquals(ms(2020, 3, 5), MediaDates.dateFromName("Screenshot_2020-03-05-10-11-12.png"))
        assertEquals(ms(2018, 12, 31), MediaDates.dateFromName("VID_20181231_235959.mp4"))
    }

    @Test
    fun numbersThatAreNotDatesAreLeftAlone() {
        assertEquals(0L, MediaDates.dateFromName("photo_1234567890123.jpg"))
        assertEquals(0L, MediaDates.dateFromName("12019081234.jpg"))
        // Month 13 and day 32 are not a date.
        assertEquals(0L, MediaDates.dateFromName("IMG_20191332.jpg"))
        assertEquals(0L, MediaDates.dateFromName("holiday.jpg"))
        assertEquals(0L, MediaDates.dateFromName(null))
    }
}
