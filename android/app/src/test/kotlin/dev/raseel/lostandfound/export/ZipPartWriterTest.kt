package dev.raseel.lostandfound.export

import java.io.File
import java.util.Random
import org.junit.Test

// Writes zips with ZipPartWriter (plain and zip64) for a few awkward sizes, with the files they
// should hold beside them, for a tool outside the JVM to check (see the build's zip-test folder).
class ZipPartWriterTest {
    @Test
    fun writesZips() {
        val dir = File("build/zip-test").apply { deleteRecursively(); mkdirs() }
        val random = Random(7)
        val sizes = listOf(0, 1, 65534, 65535, 65536, 131070, 200_001)
        val names = sizes.mapIndexed { i, s -> "Beach/Images/photo $i (size $s) é.jpg" } + "Beach/Videos/clip.mp4"
        val datas = (sizes + 3_000_000).map { ByteArray(it).also(random::nextBytes) }
        for (zip64 in listOf(false, true)) {
            val file = File(dir, if (zip64) "zip64.zip" else "plain.zip")
            ZipPartWriter(file.outputStream().buffered(), zip64).use { zip ->
                for (i in names.indices) zip.addFile(names[i], 1_700_000_000_000L + i * 86_400_000L, datas[i].inputStream())
                zip.addBytes("list.json", 0L, "{\"hello\":\"world\"}".toByteArray())
            }
        }
        val expected = File(dir, "expected").apply { mkdirs() }
        for (i in names.indices) File(expected, "$i.bin").writeBytes(datas[i])
        File(expected, "names.txt").writeText(names.joinToString("\n"))
        File(expected, "list.json").writeText("{\"hello\":\"world\"}")
    }
}
