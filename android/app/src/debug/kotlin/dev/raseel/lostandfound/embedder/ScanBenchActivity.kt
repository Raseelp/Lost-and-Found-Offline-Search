package dev.raseel.lostandfound.embedder

import android.app.Activity
import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.view.WindowManager
import android.widget.ScrollView
import android.widget.TextView
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import java.io.File
import java.nio.FloatBuffer
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.Future

/**
 * DEBUG BUILDS ONLY. Times the image model the way a scan runs it - real camera photos decoded on 2 background
 * threads while the previous batch of 4 is in the model - with different numbers of XNNPACK threads, interleaved so
 * that the phone warming up does not favour one of them.
 *
 *   adb shell pm grant dev.raseel.lostandfound.debug android.permission.READ_MEDIA_IMAGES
 *   adb shell am start -n dev.raseel.lostandfound.debug/dev.raseel.lostandfound.embedder.ScanBenchActivity
 *   adb logcat -s LostFoundBench
 */
class ScanBenchActivity : Activity() {

    private lateinit var status: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        status = TextView(this).apply {
            textSize = 13f
            setPadding(32, 96, 32, 32)
        }
        setContentView(ScrollView(this).apply { addView(status) })
        say("Timing the image model inside a scan-like pipeline. Leave the phone alone until it says done.")
        Thread({ run() }, "scan-bench").start()
    }

    private fun say(text: String) {
        Log.i(BenchLog.TAG, "scanbench: $text")
        runOnUiThread { status.append(text + "\n") }
    }

    private fun run() {
        try {
            val all = File("/sdcard/DCIM/Camera").listFiles { f -> f.name.endsWith(".jpg", true) }?.sortedBy { it.name }
                ?: emptyList()
            if (all.size < 60) {
                say("not enough camera photos readable (${all.size}): grant READ_MEDIA_IMAGES")
                return
            }
            val count = 48
            val step = all.size / count
            val photos = (0 until count).map { all[it * step] }
            say("${photos.size} real photos from ${all.size}, ${BenchLog.device(this)}")

            val model = File(cacheDir, "scanbench_vision.onnx")
            if (!model.exists()) assets.open("mobileclip_s0_vision.onnx").use { i -> model.outputStream().use { i.copyTo(it) } }
            val env = OrtEnvironment.getEnvironment()

            // First run is only a warm-up (file cache, JIT of the kernels), not reported as a result.
            runOnce(env, model, photos, 8, warmup = true)
            val order = listOf(8, 6, 4, 8, 6, 4, 8, 6, 4)
            val results = HashMap<Int, MutableList<Double>>()
            for (t in order) {
                val perImage = runOnce(env, model, photos, t, warmup = false)
                results.getOrPut(t) { ArrayList() }.add(perImage)
            }
            for ((t, v) in results.toSortedMap()) {
                say("XNNPACK $t threads: wall per image over 3 runs ${v.joinToString { "%.0f".format(it) }} ms, mean ${"%.0f".format(v.average())}")
            }
            say("done")
        } catch (e: Throwable) {
            say("failed: ${e.javaClass.simpleName}: ${e.message}")
        }
    }

    // Returns the wall time per image of the whole pipeline.
    private fun runOnce(env: OrtEnvironment, model: File, photos: List<File>, threads: Int, warmup: Boolean): Double {
        val options = OrtSession.SessionOptions()
        options.setIntraOpNumThreads(1)
        options.addXnnpack(mapOf("intra_op_num_threads" to threads.toString()))
        val session = env.createSession(model.absolutePath, options)
        val pool = Executors.newFixedThreadPool(2)
        val decodeNs = java.util.concurrent.atomic.AtomicLong()
        fun submit(chunk: List<File>): List<Future<FloatArray?>> = chunk.map { f ->
            pool.submit(Callable {
                val t = System.nanoTime()
                val r = ImagePreprocessor.loadAsFloatArray(this, Uri.fromFile(f))
                decodeNs.addAndGet(System.nanoTime() - t)
                r
            })
        }

        val chunks = photos.chunked(4)
        var inferNs = 0L
        var waitNs = 0L
        var images = 0
        val started = System.nanoTime()
        var prefetched: List<Future<FloatArray?>>? = null
        for (i in chunks.indices) {
            val current = prefetched ?: submit(chunks[i])
            prefetched = if (i + 1 < chunks.size) submit(chunks[i + 1]) else null
            val w = System.nanoTime()
            val tensors = current.mapNotNull { it.get() }
            waitNs += System.nanoTime() - w
            if (tensors.isEmpty()) continue
            val data = FloatArray(tensors.size * 3 * 256 * 256)
            for ((k, t) in tensors.withIndex()) System.arraycopy(t, 0, data, k * t.size, t.size)
            val t0 = System.nanoTime()
            OnnxTensor.createTensor(env, FloatBuffer.wrap(data), longArrayOf(tensors.size.toLong(), 3, 256, 256)).use { x ->
                session.run(mapOf(session.inputNames.first() to x)).use { }
            }
            inferNs += System.nanoTime() - t0
            images += tensors.size
        }
        val wall = (System.nanoTime() - started) / 1e6
        pool.shutdown()
        session.close()
        options.close()
        val perWall = wall / images
        if (!warmup) {
            say(
                "XNNPACK $threads threads: $images images, wall ${"%.0f".format(perWall)} ms per image " +
                    "(${"%.1f".format(1000 / perWall)}/s), infer ${"%.0f".format(inferNs / 1e6 / images)} ms, " +
                    "waiting for decode ${"%.0f".format(waitNs / 1e6 / images)} ms, decode ${"%.0f".format(decodeNs.get() / 1e6 / images)} ms (on 2 threads) | ${BenchLog.device(this)}",
            )
        }
        return perWall
    }
}
