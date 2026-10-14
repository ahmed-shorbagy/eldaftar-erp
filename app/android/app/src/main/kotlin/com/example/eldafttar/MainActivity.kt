package com.example.eldafttar

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.content.ActivityNotFoundException
import android.net.Uri

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
    }
}
