package dev.raseel.lostandfound.features.export

import java.io.File
import java.util.zip.ZipFile
import kotlin.random.Random
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** Reads the zips back with the JDK's own zip reader and checks every name and every byte. */
class ZipPartWriterReadBackTest {
    @get:Rule
    val folder = TemporaryFolder()

    private val sizes = listOf(0, 1, 65534, 65535, 65536, 131070, 200_001)
    private val names = sizes.mapIndexed { i, s -> "Beach/Images/photo $i (size $s) é.jpg" }
    private val datas = sizes.map { ByteArray(it).also(Random(it)::nextBytes) }

    private fun write(zip64: Boolean): File {
        val file = folder.newFile(if (zip64) "z64.zip" else "plain.zip")
        ZipPartWriter(file.outputStream().buffered(), zip64).use { zip ->
            for (i in names.indices) zip.addFile(names[i], 1_700_000_000_000L + i * 86_400_000L, datas[i].inputStream())
            zip.addBytes("list.json", 0L, "{\"a\":1}".toByteArray())
        }
        return file
    }

    private fun check(zip64: Boolean) {
        ZipFile(write(zip64)).use { zip ->
            assertEquals(names.size + 1, zip.size())
            for (i in names.indices) {
                val entry = zip.getEntry(names[i])
                assertTrue("missing ${names[i]}", entry != null)
                assertArrayEquals("bytes of ${names[i]}", datas[i], zip.getInputStream(entry).readBytes())
            }
            assertEquals("{\"a\":1}", zip.getInputStream(zip.getEntry("list.json")).readBytes().decodeToString())
        }
    }

    @Test
    fun aPlainZipHoldsEveryFileExactly() = check(zip64 = false)

    @Test
    fun aZip64ZipHoldsEveryFileExactly() = check(zip64 = true)

    @Test
    fun entriesComeBackInTheOrderTheyWereAdded() {
        ZipFile(write(false)).use { zip ->
            assertEquals(names + "list.json", zip.entries().asSequence().map { it.name }.toList())
        }
    }

    @Test
    fun aZipWithNothingAddedIsStillAValidEmptyZip() {
        val file = folder.newFile("empty.zip")
        ZipPartWriter(file.outputStream().buffered(), false).use { }
        ZipFile(file).use { assertEquals(0, it.size()) }
    }
}
