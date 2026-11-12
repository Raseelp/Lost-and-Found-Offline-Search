package dev.raseel.lostandfound.features.people

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ModelKeysTest {
    @Test
    fun theSameKeyIsTheSameModels() {
        assertTrue(ModelKeys.same("det|emb", "det|emb"))
    }

    @Test
    fun theBundledPrefixIsIgnored() {
        assertTrue(ModelKeys.same(".bundled_det|.bundled_emb", "det|emb"))
    }

    @Test
    fun differentKeysAreDifferentModels() {
        assertFalse(ModelKeys.same("det|emb", "det|other"))
    }

    @Test
    fun noKeyNamesNoModels() {
        assertFalse(ModelKeys.same(null, "det|emb"))
        assertFalse(ModelKeys.same("det|emb", null))
    }

    @Test
    fun nothingStoredYetCanUseAnyModels() {
        assertTrue(ModelKeys.usable(null, "det|emb"))
    }

    @Test
    fun storedPeopleCanOnlyBeUsedWithTheSameModels() {
        assertTrue(ModelKeys.usable("det|emb", "det|emb"))
        assertFalse(ModelKeys.usable("det|emb", "det|other"))
    }

    @Test
    fun noModelsInUseCannotBeUsed() {
        assertFalse(ModelKeys.usable(null, null))
        assertFalse(ModelKeys.usable("det|emb", null))
    }
}
