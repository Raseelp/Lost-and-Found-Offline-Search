package dev.raseel.lostandfound.features.library

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AutoIndexRulesTest {
    @Test
    fun nothingNewMeansNothingToDo() {
        assertEquals(AutoPlan.NOTHING, AutoIndexRules.plan(0))
        assertEquals(AutoPlan.NOTHING, AutoIndexRules.plan(0, canTell = false))
    }

    @Test
    fun aFewNewFilesAreIndexedWithoutAWord() {
        assertEquals(AutoPlan.SILENT, AutoIndexRules.plan(1))
        assertEquals(AutoPlan.SILENT, AutoIndexRules.plan(10))
    }

    @Test
    fun somewhatMoreAreIndexedWithANotification() {
        assertEquals(AutoPlan.WITH_NOTIFICATION, AutoIndexRules.plan(11))
        assertEquals(AutoPlan.WITH_NOTIFICATION, AutoIndexRules.plan(100))
    }

    @Test
    fun aBigBatchIsAskedAboutAndNeverIndexedOnItsOwn() {
        assertEquals(AutoPlan.ASK, AutoIndexRules.plan(101))
        assertEquals(AutoPlan.ASK, AutoIndexRules.plan(50_000))
    }

    @Test
    fun withoutNotificationsOnlyTheSilentSizeIsIndexed() {
        assertEquals(AutoPlan.SILENT, AutoIndexRules.plan(1, canTell = false))
        assertEquals(AutoPlan.SILENT, AutoIndexRules.plan(10, canTell = false))
        assertEquals(AutoPlan.LEAVE, AutoIndexRules.plan(11, canTell = false))
        assertEquals(AutoPlan.LEAVE, AutoIndexRules.plan(100, canTell = false))
        assertEquals(AutoPlan.LEAVE, AutoIndexRules.plan(101, canTell = false))
    }

    @Test
    fun aQuestionThatWasSwipedAwayStaysQuietForADayUnlessTheBatchGrows() {
        val at = 1_000_000L
        assertTrue(AutoIndexRules.askIsQuiet(at + 1000, at, 150, 150))
        assertTrue(AutoIndexRules.askIsQuiet(at + 1000, at, 150, 120))
        assertFalse(AutoIndexRules.askIsQuiet(at + 1000, at, 150, 151))
        assertFalse(AutoIndexRules.askIsQuiet(at + AutoIndexRules.ASK_QUIET_MS, at, 150, 150))
        assertTrue(AutoIndexRules.askIsQuiet(at + AutoIndexRules.ASK_QUIET_MS - 1, at, 150, 150))
    }

    @Test
    fun aQuestionThatWasNeverSwipedAwayIsNotQuiet() {
        assertFalse(AutoIndexRules.askIsQuiet(5_000, 0L, 0, 150))
    }

    @Test
    fun aClockSetBackDoesNotSilenceTheQuestionForLonger() {
        assertFalse(AutoIndexRules.askIsQuiet(500, 1_000_000L, 150, 150))
    }

    @Test
    fun aFileModifiedLongBeforeTheMarkerIsNotNew() {
        assertEquals(10_000L - 3600L, AutoIndexRules.modifiedFloor(10_000L))
        assertEquals(0L, AutoIndexRules.modifiedFloor(100L))
    }
}
