package com.example.eldafttar

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.content.ActivityNotFoundException
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "eldafttar/customer_contact")
            .setMethodCallHandler { call, result ->
                if (call.method != "canOpenDialer" && call.method != "openDialer") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val destination = call.arguments as? String
                if (destination == null || !Regex("^tel:\\+[1-9][0-9]{6,14}$").matches(destination)) {
                    result.error("invalid_destination", null, null)
                    return@setMethodCallHandler
                }
                // ACTION_DIAL prepopulates the system UI and cannot place a call.
                val intent = Intent(Intent.ACTION_DIAL, Uri.parse(destination))
                try {
                    if (call.method == "canOpenDialer") {
                        result.success(intent.resolveActivity(packageManager) != null)
                    } else {
                        startActivity(intent)
                        result.success(true)
                    }
                } catch (_: ActivityNotFoundException) {
                    result.success(false)
                } catch (_: SecurityException) {
                    result.error("PERMISSION_DENIED", null, null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "eldafttar/whatsapp_share")
            .setMethodCallHandler { call, result ->
                if (call.method != "sharePdf") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                val phone = call.argument<String>("phone")
                val text = call.argument<String>("text") ?: ""
                val invoices = File(cacheDir, "invoices")
                val file = path?.let { File(it) }
                if (file == null ||
                    phone != null && !Regex("^[1-9][0-9]{6,14}$").matches(phone) ||
                    !file.canonicalFile.path.startsWith(invoices.canonicalFile.path + File.separator)
                ) {
                    result.error("invalid", null, null)
                    return@setMethodCallHandler
                }
                val uri = FileProvider.getUriForFile(
                    this,
                    "$packageName.invoicefiles",
                    file,
                )
                fun send(packageName: String) {
                    val intent = Intent(Intent.ACTION_SEND).apply {
                        type = "application/pdf"
                        putExtra(Intent.EXTRA_STREAM, uri)
                        putExtra(Intent.EXTRA_TEXT, text)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        if (phone != null) putExtra("jid", "$phone@s.whatsapp.net")
                        setPackage(packageName)
                    }
                    startActivity(intent)
                }
                try {
                    send("com.whatsapp")
                    result.success("opened")
                } catch (_: ActivityNotFoundException) {
                    try {
                        send("com.whatsapp.w4b")
                        result.success("opened")
                    } catch (_: ActivityNotFoundException) {
                        result.success("not_installed")
                    }
                }
            }
    }
}
