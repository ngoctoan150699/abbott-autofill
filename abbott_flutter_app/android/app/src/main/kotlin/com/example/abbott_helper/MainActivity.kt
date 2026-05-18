package com.example.abbott_helper

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val preferencesChannel = "abbott_helper/preferences"
    private val preferencesName = "abbott_helper_preferences"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, preferencesChannel).setMethodCallHandler { call, result ->
            val preferences = getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
            val key = call.argument<String>("key")

            if (key.isNullOrBlank()) {
                result.error("invalid_key", "Preference key is required", null)
                return@setMethodCallHandler
            }

            when (call.method) {
                "getString" -> result.success(preferences.getString(key, null))
                "setString" -> {
                    val value = call.argument<String>("value") ?: ""
                    preferences.edit().putString(key, value).apply()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
