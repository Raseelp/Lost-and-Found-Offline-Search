package dev.raseel.lostandfound.embedder.storage

import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class EmbeddingStoreHeaderTest {

    private val magic = 0x454D4244

    private fun header(vararg ints: Int): ByteArray {
        val bytes = ByteArrayOutputStream()
        DataOutputStream(bytes).use { out -> ints.forEach { out.writeInt(it) } }
        return bytes.toByteArray()
    }

    @Test
    fun aFileOfTheOldVersionWasMadeByTheFirstModel() {
        // magic, version 2, 512 numbers per vector: and no model id (the first record follows).
        assertEquals(1, EmbeddingStore.modelOfHeader(header(magic, 2, 512)))
        assertEquals(1, EmbeddingStore.modelOfHeader(header(magic, 2, 512, 7, 7)))
    }

    @Test
    fun aCurrentFileSaysWhichModelMadeIt() {
        assertEquals(EmbeddingStore.MODEL_ID, EmbeddingStore.modelOfHeader(header(magic, 3, 512, EmbeddingStore.MODEL_ID)))
        assertEquals(9, EmbeddingStore.modelOfHeader(header(magic, 3, 512, 9)))
    }

    @Test
    fun theCurrentModelIsNotTheOneOfTheOldFiles() {
        // What makes an index from before the switch be dropped.
        assert(EmbeddingStore.MODEL_ID != EmbeddingStore.modelOfHeader(header(magic, 2, 512)))
    }

    @Test
    fun somethingThatIsNotAnIndexHasNoModel() {
        assertNull(EmbeddingStore.modelOfHeader(header(123, 3, 512, 2)))
        assertNull(EmbeddingStore.modelOfHeader(ByteArray(0)))
        assertNull(EmbeddingStore.modelOfHeader(header(magic, 3)))
        // A new-version file cut short before the model id.
        assertNull(EmbeddingStore.modelOfHeader(header(magic, 3, 512)))
    }
}
