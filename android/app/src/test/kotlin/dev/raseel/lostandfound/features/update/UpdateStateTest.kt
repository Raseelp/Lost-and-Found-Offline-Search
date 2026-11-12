package dev.raseel.lostandfound.features.update

import com.google.android.play.core.install.model.InstallStatus
import com.google.android.play.core.install.model.UpdateAvailability
import org.junit.Assert.assertEquals
import org.junit.Test

class UpdateStateTest {
    @Test
    fun noUpdateIsNone() {
        assertEquals("none", UpdateState.of(InstallStatus.UNKNOWN, UpdateAvailability.UPDATE_NOT_AVAILABLE, true))
        assertEquals("none", UpdateState.of(InstallStatus.UNKNOWN, UpdateAvailability.UNKNOWN, true))
    }

    @Test
    fun anUpdateThatCanBeInstalledInTheBackgroundIsAvailable() {
        assertEquals("available", UpdateState.of(InstallStatus.UNKNOWN, UpdateAvailability.UPDATE_AVAILABLE, true))
    }

    @Test
    fun anUpdateThatCannotBeInstalledInTheBackgroundIsNotOffered() {
        assertEquals("none", UpdateState.of(InstallStatus.UNKNOWN, UpdateAvailability.UPDATE_AVAILABLE, false))
    }

    @Test
    fun aDownloadInProgressComesBeforeAvailable() {
        assertEquals("downloading", UpdateState.of(InstallStatus.DOWNLOADING, UpdateAvailability.UPDATE_AVAILABLE, true))
        assertEquals("downloading", UpdateState.of(InstallStatus.PENDING, UpdateAvailability.UPDATE_AVAILABLE, true))
    }

    @Test
    fun aDownloadedUpdateIsReadyToInstall() {
        assertEquals("downloaded", UpdateState.of(InstallStatus.DOWNLOADED, UpdateAvailability.UPDATE_AVAILABLE, false))
    }
}
