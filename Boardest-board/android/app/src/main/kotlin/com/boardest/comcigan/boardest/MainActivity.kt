package com.boardest.comcigan.boardest

import android.content.Context
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.boardest/launch_args"
    private var launchTool: String? = null
    private var methodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
        createDynamicShortcuts()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
        val tool = launchTool
        if (tool != null) {
            methodChannel?.invokeMethod("onNewLaunchArgs", tool)
            launchTool = null
        }
    }

    override fun onBackPressed() {
        if (isTaskRoot) {
            return
        }
        super.onBackPressed()
    }

    private fun handleIntent(intent: Intent?) {
        if (intent != null && intent.hasExtra("tool")) {
            launchTool = intent.getStringExtra("tool")
        }
    }

    private fun createDynamicShortcuts() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
            val shortcutManager = getSystemService(ShortcutManager::class.java)
            if (shortcutManager != null) {
                val shortcuts = mutableListOf<ShortcutInfo>()

                val tools = listOf(
                    Triple("whiteboard", "판서", android.R.drawable.ic_menu_edit),
                    Triple("timer", "타이머", android.R.drawable.ic_menu_recent_history),
                    Triple("picker", "발표자", android.R.drawable.ic_menu_search),
                    Triple("dice", "주사위", android.R.drawable.ic_menu_gallery),
                    Triple("timetable", "전체시간표", android.R.drawable.ic_menu_today),
                    Triple("noise", "소음측정", android.R.drawable.ic_menu_compass),
                    Triple("settings", "환경설정", android.R.drawable.ic_menu_preferences)
                )

                for (tool in tools) {
                    val shortcutIntent = Intent(this, MainActivity::class.java).apply {
                        action = Intent.ACTION_MAIN
                        putExtra("tool", tool.first)
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                    }

                    val shortcut = ShortcutInfo.Builder(this, tool.first)
                        .setShortLabel(tool.second)
                        .setLongLabel(tool.second)
                        .setIcon(Icon.createWithResource(this, tool.third))
                        .setIntent(shortcutIntent)
                        .build()
                    shortcuts.add(shortcut)
                }

                try {
                    shortcutManager.dynamicShortcuts = shortcuts
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getLaunchTool" -> {
                    val tool = launchTool
                    launchTool = null
                    result.success(tool)
                }
                "listInstalledApps" -> {
                    try {
                        val pm = packageManager
                        val intent = Intent(Intent.ACTION_MAIN, null).apply {
                            addCategory(Intent.CATEGORY_LAUNCHER)
                        }
                        @Suppress("DEPRECATION")
                        val activities = pm.queryIntentActivities(intent, 0)
                        val seen = mutableSetOf<String>()
                        val list = mutableListOf<Map<String, String>>()
                        for (info in activities) {
                            val pkg = info.activityInfo.packageName ?: continue
                            if (pkg == packageName || seen.contains(pkg)) continue
                            seen.add(pkg)
                            val label = info.loadLabel(pm)?.toString() ?: pkg
                            list.add(mapOf("name" to label, "appId" to pkg))
                        }
                        list.sortBy { it["name"]?.lowercase() }
                        result.success(list)
                    } catch (e: Exception) {
                        result.error("ERR_APPS", e.message, null)
                    }
                }
                "launchApp" -> {
                    val pkg = call.argument<String>("packageName")
                    if (pkg.isNullOrBlank()) {
                        result.error("ERR_ARGS", "packageName required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val launchIntent = packageManager.getLaunchIntentForPackage(pkg)
                        if (launchIntent != null) {
                            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(launchIntent)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        result.error("ERR_LAUNCH", e.message, null)
                    }
                }
                "openUsbStorage" -> {
                    val path = call.arguments as? String
                    try {
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            if (!path.isNullOrBlank()) {
                                data = android.net.Uri.parse("file://$path")
                            }
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        val chooser = Intent.createChooser(intent, "USB 열기")
                        chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(chooser)
                        result.success(true)
                    } catch (e: Exception) {
                        try {
                            val docs = Intent(Intent.ACTION_VIEW).apply {
                                setClassName(
                                    "com.android.documentsui",
                                    "com.android.documentsui.files.FilesActivity"
                                )
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(docs)
                            result.success(true)
                        } catch (ex: Exception) {
                            result.error("ERR_USB", ex.message, null)
                        }
                    }
                }
                "openHomeSettings" -> {
                    try {
                        val intent = Intent(android.provider.Settings.ACTION_HOME_SETTINGS).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        try {
                            val intent = Intent(android.provider.Settings.ACTION_SETTINGS).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(intent)
                            result.success(false)
                        } catch (ex: Exception) {
                            result.error("ERR_LAUNCH", ex.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
