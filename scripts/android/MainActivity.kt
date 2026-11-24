// ---------------------------------------------------------------------------
// Datei:        scripts/android/MainActivity.kt  (Vorlage)
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.24.12.00.00
//
// Beschreibung: MainActivity der Android-App. scripts/setup_platforms.sh
//               kopiert diese Vorlage nach android/app/src/main/kotlin/…
//               (dort nicht von Hand ändern — beim nächsten Lauf weg).
//
//               * FlutterFragmentActivity: local_auth zeigt den
//                 Biometrie-Dialog als Fragment.
//               * Kanal "de.phytech.rimperio/updater": App-Update aus dem
//                 GitHub-Release. Die APK lädt die Dart-Seite in den Cache,
//                 hier wird die Prüfsumme (SHA-256 aus dem Release) geprüft
//                 und die Datei über den PackageInstaller eingespielt.
//                 Android fragt dabei immer selbst nach („Aktualisieren?“)
//                 und spielt nur ein, was mit demselben Schlüssel signiert
//                 ist wie die installierte App.
//
//               Die Berechtigung REQUEST_INSTALL_PACKAGES kommt nur in die
//               APK (scripts/self_update_permission.sh) — das Play-Store-
//               Bundle hat sie nicht, dort meldet "info" declared=false und
//               die App bietet kein Selbst-Update an.
// ---------------------------------------------------------------------------
package __PACKAGE__

import android.Manifest
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

class MainActivity : FlutterFragmentActivity() {
    private var updater: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        updater = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "info" -> result.success(
                    mapOf(
                        "cacheDir" to cacheDir.absolutePath,
                        "declared" to declaresInstallPermission(),
                        "canInstall" to canInstall(),
                        "sdk" to Build.VERSION.SDK_INT,
                    )
                )
                "openInstallSettings" -> {
                    openInstallSettings()
                    result.success(null)
                }
                "install" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("args", "Pfad fehlt", null)
                    } else {
                        install(path, call.argument<String>("sha256"), result)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        updater?.setMethodCallHandler(null)
        updater = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun declaresInstallPermission(): Boolean = try {
        val info = if (Build.VERSION.SDK_INT >= 33) {
            packageManager.getPackageInfo(
                packageName, PackageManager.PackageInfoFlags.of(PackageManager.GET_PERMISSIONS.toLong())
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, PackageManager.GET_PERMISSIONS)
        }
        info.requestedPermissions?.contains(Manifest.permission.REQUEST_INSTALL_PACKAGES) == true
    } catch (e: Exception) {
        false
    }

    /** Darf RIMPERIO Apps installieren („Unbekannte Apps installieren“)? */
    private fun canInstall(): Boolean =
        declaresInstallPermission() &&
            (Build.VERSION.SDK_INT < 26 || packageManager.canRequestPackageInstalls())

    private fun openInstallSettings() {
        val intent = if (Build.VERSION.SDK_INT >= 26) {
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
        } else {
            @Suppress("DEPRECATION")
            Intent(Settings.ACTION_SECURITY_SETTINGS)
        }
        try {
            startActivity(intent)
        } catch (e: Exception) {
            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
        }
    }

    private fun sha256(file: File): String {
        val md = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buf = ByteArray(1 shl 16)
            while (true) {
                val n = input.read(buf)
                if (n < 0) break
                md.update(buf, 0, n)
            }
        }
        return md.digest().joinToString("") { "%02x".format(it) }
    }

    private fun install(path: String, expectedSha256: String?, result: MethodChannel.Result) {
        Thread {
            try {
                val file = File(path)
                if (!file.isFile) throw IllegalStateException("Download nicht gefunden")
                if (!expectedSha256.isNullOrBlank()) {
                    val actual = sha256(file)
                    if (!actual.equals(expectedSha256.trim(), ignoreCase = true)) {
                        file.delete()
                        runOnUiThread {
                            result.error("checksum", "Prüfsumme stimmt nicht – Download beschädigt oder verändert.", null)
                        }
                        return@Thread
                    }
                }
                val installer = packageManager.packageInstaller
                val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
                params.setAppPackageName(packageName)
                val sessionId = installer.createSession(params)
                installer.openSession(sessionId).use { session ->
                    file.inputStream().use { input ->
                        session.openWrite("rimperio.apk", 0, file.length()).use { out ->
                            input.copyTo(out, 1 shl 16)
                            session.fsync(out)
                        }
                    }
                    // Rückmeldung kommt als neuer Intent an diese Activity
                    // (onNewIntent) — explizit, damit es auch unter Android 14+
                    // ein veränderbarer PendingIntent sein darf.
                    val status = Intent(this, MainActivity::class.java)
                        .setAction(ACTION_INSTALL_STATUS)
                        .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    var flags = PendingIntent.FLAG_UPDATE_CURRENT
                    if (Build.VERSION.SDK_INT >= 31) flags = flags or PendingIntent.FLAG_MUTABLE
                    val pending = PendingIntent.getActivity(this, sessionId, status, flags)
                    session.commit(pending.intentSender)
                }
                runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                runOnUiThread { result.error("install", e.message ?: e.javaClass.simpleName, null) }
            }
        }.start()
    }

    override fun onNewIntent(intent: Intent) {
        if (intent.action != ACTION_INSTALL_STATUS) {
            super.onNewIntent(intent)
            return
        }
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirm: Intent? = if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_INTENT)
                }
                if (confirm != null) {
                    try {
                        startActivity(confirm)
                        updater?.invokeMethod("status", mapOf("state" to "confirm"))
                    } catch (e: Exception) {
                        updater?.invokeMethod(
                            "status", mapOf("state" to "failed", "status" to status, "message" to e.message)
                        )
                    }
                }
            }
            PackageInstaller.STATUS_SUCCESS ->
                updater?.invokeMethod("status", mapOf("state" to "done"))
            else -> updater?.invokeMethod(
                "status",
                mapOf(
                    "state" to "failed",
                    "status" to status,
                    "message" to intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE),
                )
            )
        }
    }

    companion object {
        private const val CHANNEL = "de.phytech.rimperio/updater"
        private const val ACTION_INSTALL_STATUS = "de.phytech.rimperio.INSTALL_STATUS"
    }
}
