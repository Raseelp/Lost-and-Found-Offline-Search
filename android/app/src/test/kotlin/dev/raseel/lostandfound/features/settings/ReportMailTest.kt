package dev.raseel.lostandfound.features.settings

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ReportMailTest {
    @Test
    fun anOrdinaryNameIsKept() {
        assertEquals("Screenshot_2026-11-11.png", ReportMail.safeName("Screenshot_2026-11-11.png", "attachment-1"))
    }

    @Test
    fun charactersAFileNameShouldNotHoldAreReplaced() {
        assertEquals("a_b_c.mp4", ReportMail.safeName("a/b\\c.mp4", "attachment-1"))
    }

    @Test
    fun aMissingOrEmptyNameFallsBack() {
        assertEquals("attachment-2", ReportMail.safeName(null, "attachment-2"))
        assertEquals("attachment-2", ReportMail.safeName("   ", "attachment-2"))
        assertEquals("attachment-2", ReportMail.safeName("..", "attachment-2"))
    }

    @Test
    fun aVeryLongNameIsCut() {
        assertEquals(80, ReportMail.safeName("a".repeat(200) + ".png", "x").length)
    }

    @Test
    fun theDefaultMailAppIsOpenedAtOnce() {
        val apps = listOf("com.google.android.gm", "com.microsoft.office.outlook")
        assertEquals("com.google.android.gm", ReportMail.chooseTarget("com.google.android.gm", apps))
    }

    @Test
    fun theOnlyMailAppIsOpenedAtOnce() {
        assertEquals("com.google.android.gm", ReportMail.chooseTarget("android", listOf("com.google.android.gm")))
    }

    @Test
    fun severalMailAppsWithNoDefaultAreAChoice() {
        val apps = listOf("com.google.android.gm", "com.microsoft.office.outlook")
        assertNull(ReportMail.chooseTarget("android", apps))
        assertNull(ReportMail.chooseTarget(null, emptyList()))
    }
}
