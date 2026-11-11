package dev.raseel.lostandfound.features.settings

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import java.io.File

/** The provider that hands the files of a problem report to the person's mail app. */
class ReportFileProvider : FileProvider()

/**
 * Builds the email for a problem report. The app sends nothing itself: the person's own mail app opens with the
 * address, the subject, the text and the files filled in, and they press Send there.
 */
object ReportMail {

    private const val SUBJECT = "Lost & Found: problem report"
    private const val FOLDER = "report"
    private const val LOG_FILE = "lost-and-found-log.txt"

    /** The files in a report are copied here, so the mail app can read them whatever happens to the originals. */
    private fun folder(context: Context) = File(context.cacheDir, FOLDER)

    fun authority(context: Context) = "${context.packageName}.reportfiles"

    /** Set when a report has been handed to a mail app, so the copies can go once the person is back in this app. */
    @Volatile
    private var handedOver = false

    /** Deletes the copies of the files of the last report. */
    fun cleanUp(context: Context) {
        folder(context).deleteRecursively()
    }

    /** Deletes the copies once the person is back from the mail app, which has made its own copy of the files by then. */
    fun cleanUpIfHandedOver(context: Context) {
        if (!handedOver) return
        handedOver = false
        cleanUp(context)
    }

    /** True if some app on the phone can write an email. */
    fun hasMailApp(context: Context): Boolean =
        context.packageManager.queryIntentActivities(Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:")), 0).isNotEmpty()

    /**
     * The intent that opens the mail app, or null when there is no mail app. It copies the attachments and, when
     * [includeLogs] is set, the app's log into the cache, so call it off the main thread.
     */
    fun build(context: Context, to: String, message: String, attachments: List<Uri>, includeLogs: Boolean): Intent? {
        if (!hasMailApp(context)) return null

        val files = folder(context)
        files.deleteRecursively()
        files.mkdirs()

        val shared = ArrayList<Uri>()
        if (includeLogs) {
            val log = File(files, LOG_FILE)
            log.writeText(LogDump.collect(context))
            shared += FileProvider.getUriForFile(context, authority(context), log)
        }
        for ((index, source) in attachments.withIndex()) {
            val copy = File(File(files, index.toString()).apply { mkdirs() }, fileName(context, source, index))
            context.contentResolver.openInputStream(source)?.use { input ->
                copy.outputStream().use { input.copyTo(it) }
            } ?: throw IllegalStateException("Could not open an attachment")
            shared += FileProvider.getUriForFile(context, authority(context), copy)
        }

        val body = message.trim() + "\n\n--\n" + LogDump.header(context)
        val intent = if (shared.isEmpty()) {
            Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:"))
        } else {
            Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                type = "message/rfc822"
                putParcelableArrayListExtra(Intent.EXTRA_STREAM, shared)
                clipData = ClipData.newRawUri("", shared.first()).also { clip ->
                    shared.drop(1).forEach { clip.addItem(ClipData.Item(it)) }
                }
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        }
        return intent.apply {
            putExtra(Intent.EXTRA_EMAIL, arrayOf(to))
            putExtra(Intent.EXTRA_SUBJECT, SUBJECT)
            putExtra(Intent.EXTRA_TEXT, body)
        }
    }

    /**
     * Opens [mail] in a mail app, and in a mail app only: the share sheet of the whole phone is never shown. It goes
     * straight to the person's default mail app, or to the only one there is. With several and no default, a short list
     * of just the mail apps is shown.
     */
    fun open(activity: Activity, mail: Intent) {
        val probe = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:"))
        val pm = activity.packageManager
        val apps = pm.queryIntentActivities(probe, 0).map { it.activityInfo }
        val packages = apps.map { it.packageName }.distinct()
        val default = pm.resolveActivity(probe, android.content.pm.PackageManager.MATCH_DEFAULT_ONLY)?.activityInfo?.packageName

        val target = chooseTarget(default, packages)
        if (target != null) {
            try {
                activity.startActivity(Intent(mail).setPackage(target))
                handedOver = true
                return
            } catch (_: ActivityNotFoundException) {
            }
        }

        val chooser = Intent.createChooser(probe, "Send with").apply {
            putExtra(Intent.EXTRA_INITIAL_INTENTS, packages.map { Intent(mail).setPackage(it) }.toTypedArray())
            putExtra(Intent.EXTRA_EXCLUDE_COMPONENTS, apps.map { ComponentName(it.packageName, it.name) }.toTypedArray())
            clipData = mail.clipData
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        activity.startActivity(chooser)
        handedOver = true
    }

    /** The mail app to open at once: the person's default one if it is a mail app, else the only one. Null when it is a choice. */
    internal fun chooseTarget(default: String?, mailApps: List<String>): String? =
        default?.takeIf { it in mailApps } ?: mailApps.singleOrNull()

    /** The name an attachment is saved under: its own name with anything a file name should not hold replaced. */
    private fun fileName(context: Context, source: Uri, index: Int): String {
        val name = context.contentResolver.query(source, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { if (it.moveToFirst()) it.getString(0) else null }
        return safeName(name, "attachment-${index + 1}")
    }

    internal fun safeName(name: String?, fallback: String): String {
        val cleaned = name.orEmpty().replace(Regex("[^A-Za-z0-9._ -]"), "_").trim().take(80)
        return if (cleaned.isEmpty() || cleaned.all { it == '.' || it == '_' }) fallback else cleaned
    }
}
