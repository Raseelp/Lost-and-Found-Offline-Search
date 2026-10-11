package dev.twentyonevision.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle

class SafPickerActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val mode = intent.getStringExtra(EXTRA_MODE) ?: MODE_FOLDER

        val pickerIntent = when (mode) {

            MODE_IMAGE -> {
                Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    type = "image/*"
                    addFlags(
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                    )
                }
            }

            // A folder to save a zip in: it has to be writable.
            MODE_EXPORT_FOLDER -> {
                Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                    addFlags(
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                    )
                }
            }

            else -> {
                Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                    addFlags(
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                    )
                }
            }
        }

        startActivityForResult(pickerIntent, REQUEST_CODE)
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?
    ) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == REQUEST_CODE && resultCode == RESULT_OK) {
            val uri: Uri? = data?.data

            if (uri != null) {

                val mode = intent.getStringExtra(EXTRA_MODE)
                contentResolver.takePersistableUriPermission(
                    uri,
                    if (mode == MODE_EXPORT_FOLDER) {
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    } else {
                        Intent.FLAG_GRANT_READ_URI_PERMISSION
                    }
                )

                val result = Intent().apply {
                    putExtra(EXTRA_URI, uri.toString())
                }

                setResult(RESULT_OK, result)

            } else {
                setResult(RESULT_CANCELED)
            }

        } else {
            setResult(RESULT_CANCELED)
        }

        finish()
    }

    companion object {
        const val REQUEST_CODE = 1001
        const val EXTRA_URI = "picked_uri"
        const val EXTRA_MODE = "picker_mode"

        const val MODE_FOLDER = "folder"
        const val MODE_IMAGE = "image"
        const val MODE_EXPORT_FOLDER = "export_folder"
    }
}
