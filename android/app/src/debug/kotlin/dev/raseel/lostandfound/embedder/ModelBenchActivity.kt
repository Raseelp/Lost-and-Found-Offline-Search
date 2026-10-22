package dev.raseel.lostandfound.embedder

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.BitmapFactory
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
import java.nio.LongBuffer
import org.json.JSONArray

/**
 * DEBUG BUILDS ONLY (a developer tool: it is not part of the release app). Checks MobileCLIP-S0, S1 and S2 on this
 * phone - are the numbers finite, does the right sample photo come first for the queries in bench_queries.json, how
 * long a search text takes - and times each image tower in several ways, on the tour's sample photos, so the models
 * and settings can be compared without touching the library or running a scan.
 *
 * The model files are too big to keep in the repo (*.onnx is ignored): export them with export_clip/export_mobileclip.py
 * (--variant s0, s1, s2) and copy mobileclip_<variant>_vision.onnx and
 * mobileclip_<variant>_text.onnx into android/app/src/debug/assets/ before building the debug app. Without them
 * this screen says "failed" and nothing else is affected.
 *
 *   adb shell am start -n dev.raseel.lostandfound.debug/dev.raseel.lostandfound.embedder.ModelBenchActivity
 *   adb logcat -s LostFoundBench
 *
 * Keep the phone awake and unplugged from other work: nothing else (a scan in another app) should be running.
 * ScanBenchActivity (next to this one) times the image tower the way a scan runs it.
 */
class ModelBenchActivity : Activity() {

    private lateinit var status: TextView
    private var photoNames: List<String> = emptyList()

    private class Variant(
        val name: String,
        val file: String,
        val intraThreads: Int? = null,
        val xnnpackThreads: Int? = null,
        val affinity: String? = null,
    )

    private val models = listOf("s0", "s1", "s2")

    private val variants = models.flatMap { m ->
        val f = "mobileclip_${m}_vision.onnx"
        listOf(
            Variant("$m fp32, default", f),
            Variant("$m fp32, 2 threads", f, intraThreads = 2),
            Variant("$m fp32, XNNPACK 4 threads", f, xnnpackThreads = 4),
            Variant("$m fp32, XNNPACK 8 threads", f, xnnpackThreads = 8),
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        status = TextView(this).apply {
            textSize = 13f
            setPadding(32, 96, 32, 32)
        }
        setContentView(ScrollView(this).apply { addView(status) })
        say("Timing the image model. Leave the phone alone until it says done (about 15 minutes).")
        Thread({ run() }, "model-bench").start()
    }

    private fun say(text: String) {
        Log.i(BenchLog.TAG, "bench: $text")
        runOnUiThread { status.append(text + "\n") }
    }

    private fun run() {
        try {
            val inputs = loadInputs()
            say("${inputs.size} sample photos prepared (256 x 256), ${BenchLog.device(this)}")
            val env = OrtEnvironment.getEnvironment()
            try {
                correctness(env, inputs)
            } catch (e: Throwable) {
                say("correctness check FAILED ${e.javaClass.simpleName}: ${e.message}")
            }
            for (v in variants) {
                try {
                    runVariant(env, v, inputs)
                } catch (e: Throwable) {
                    say("${v.name}: FAILED ${e.javaClass.simpleName}: ${e.message}")
                }
            }
            say("done")
        } catch (e: Throwable) {
            say("failed: ${e.javaClass.simpleName}: ${e.message}")
        }
    }

    private fun loadInputs(): List<FloatArray> {
        val dir = "flutter_assets/assets/tour/photos"
        val names = (assets.list(dir) ?: emptyArray()).filter { it.endsWith(".jpg") }.sorted()
        photoNames = names.map { it.removeSuffix(".jpg") }
        return names.mapNotNull { n ->
            val bitmap: Bitmap = assets.open("$dir/$n").use { BitmapFactory.decodeStream(it) } ?: return@mapNotNull null
            ImagePreprocessor.bitmapToFloatArray(bitmap).also { bitmap.recycle() }
        }
    }

    // Each model's two towers on this phone: are the numbers finite, does the right photo come first for the queries,
    // and how long does one search text take?
    private fun correctness(env: OrtEnvironment, inputs: List<FloatArray>) {
        val queries = JSONArray(assets.open("bench_queries.json").bufferedReader().use { it.readText() })
        for (m in models) {
            val textSession = env.createSession(modelFile("mobileclip_${m}_text.onnx").absolutePath, OrtSession.SessionOptions())
            val textMs = ArrayList<Double>()
            val texts = Array(queries.length()) { i ->
                val tokens = queries.getJSONObject(i).getJSONArray("tokens")
                val ids = LongArray(77) { tokens.getLong(it) }
                val t0 = System.nanoTime()
                OnnxTensor.createTensor(env, LongBuffer.wrap(ids), longArrayOf(1, 77)).use { t ->
                    textSession.run(mapOf(textSession.inputNames.first() to t)).use { r ->
                        val b = (r[0] as OnnxTensor).floatBuffer
                        FloatArray(b.remaining()).also { b.get(it) }
                    }
                }.also { textMs += (System.nanoTime() - t0) / 1_000_000.0 }
            }
            textSession.close()
            val sortedText = textMs.drop(1).sorted()
            say(
                "$m text model: ${texts.count { v -> v.any { !it.isFinite() } }} of ${texts.size} query vectors with NaN/infinite numbers, " +
                    "median ${"%.0f".format(sortedText[sortedText.size / 2])} ms per search text",
            )

            val session = env.createSession(modelFile("mobileclip_${m}_vision.onnx").absolutePath, OrtSession.SessionOptions())
            val photos = ArrayList<FloatArray>()
            for (i in inputs.indices) {
                OnnxTensor.createTensor(env, FloatBuffer.wrap(inputs[i]), longArrayOf(1, 3, 256, 256)).use { t ->
                    session.run(mapOf(session.inputNames.first() to t)).use { r ->
                        val b = (r[0] as OnnxTensor).floatBuffer
                        photos += FloatArray(b.remaining()).also { b.get(it) }
                    }
                }
            }
            session.close()
            val badPhotos = photos.count { v -> v.any { !it.isFinite() } }
            var first = 0
            var top3 = 0
            for (i in 0 until queries.length()) {
                val right = queries.getJSONObject(i).getJSONArray("right")
                val rightNames = (0 until right.length()).map { right.getString(it) }
                val scores = photos.map { p -> var d = 0.0; for (k in p.indices) d += p[k] * texts[i][k]; d }
                val order = scores.indices.sortedByDescending { if (scores[it].isNaN()) Double.NEGATIVE_INFINITY else scores[it] }
                val rank = order.indexOfFirst { photoNames[it] in rightNames } + 1
                if (rank == 1) first++
                if (rank in 1..3) top3++
            }
            say(
                "$m image model: $badPhotos of ${photos.size} photo vectors with NaN/infinite numbers; " +
                    "right photo first for $first of ${queries.length()} queries, in the top 3 for $top3",
            )
        }
    }

    private fun modelFile(name: String): File {
        val target = File(cacheDir, "bench_$name")
        if (!target.exists()) {
            assets.open(name).use { input -> target.outputStream().use { input.copyTo(it) } }
        }
        return target
    }

    private fun runVariant(env: OrtEnvironment, v: Variant, inputs: List<FloatArray>) {
        val options = OrtSession.SessionOptions()
        v.intraThreads?.let { options.setIntraOpNumThreads(it) }
        v.affinity?.let { options.addConfigEntry("session.intra_op_thread_affinities", it) }
        v.xnnpackThreads?.let {
            options.setIntraOpNumThreads(1)
            options.addXnnpack(mapOf("intra_op_num_threads" to it.toString()))
        }
        val path = modelFile(v.file).absolutePath
        val loadStart = System.nanoTime()
        val session = env.createSession(path, options)
        val loadMs = (System.nanoTime() - loadStart) / 1_000_000

        val batch = 4
        val shape = longArrayOf(batch.toLong(), 3, 256, 256)
        val per = 3 * 256 * 256
        fun makeBatch(first: Int): FloatArray {
            val data = FloatArray(batch * per)
            for (i in 0 until batch) System.arraycopy(inputs[(first + i) % inputs.size], 0, data, i * per, per)
            return data
        }

        fun infer(data: FloatArray): FloatArray =
            OnnxTensor.createTensor(env, FloatBuffer.wrap(data), shape).use { tensor ->
                session.run(mapOf(session.inputNames.first() to tensor)).use { result ->
                    val buffer = (result[0] as OnnxTensor).floatBuffer
                    FloatArray(buffer.remaining()).also { buffer.get(it) }
                }
            }

        val first = infer(makeBatch(0)) // also the warm-up
        val times = ArrayList<Double>()
        var broken = first.count { !it.isFinite() }
        for (b in 0 until 8) {
            val data = makeBatch(b * batch)
            val t = System.nanoTime()
            val out = infer(data)
            times += (System.nanoTime() - t) / 1_000_000.0 / batch
            broken += out.count { !it.isFinite() }
        }
        session.close()
        options.close()

        val sorted = times.sorted()
        val median = sorted[sorted.size / 2]
        say(
            "${v.name}: median ${"%.0f".format(median)} ms per image (mean ${"%.0f".format(times.average())}, " +
                "best ${"%.0f".format(sorted.first())}, worst ${"%.0f".format(sorted.last())}), load $loadMs ms" +
                ", NaN/infinite numbers in the answers: $broken" +
                " | ${BenchLog.device(this)}",
        )
    }
}
