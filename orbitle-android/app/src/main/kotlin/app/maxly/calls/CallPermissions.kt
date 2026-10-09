package app.maxly.calls

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import app.maxly.data.calls.CallLog
import kotlinx.coroutines.CompletableDeferred

/**
 * Разрешения звонка: микрофон, камера, уведомления и показ экрана. Их спрашивает активити;
 * без неё (приложение в фоне) просьба сразу отвечает «нет».
 */
object CallPermissions {
    private var context: Context? = null
    private var permissionLauncher: ActivityResultLauncher<String>? = null
    private var screenLauncher: ActivityResultLauncher<Intent>? = null
    private var pendingPermission: CompletableDeferred<Boolean>? = null
    private var pendingScreen: CompletableDeferred<Intent?>? = null

    const val MICROPHONE_DENIED = "Нет доступа к микрофону. Разрешите его Maxly в настройках, чтобы звонить."

    fun init(context: Context) {
        this.context = context.applicationContext
    }

    /** Активити регистрирует просьбы в `onCreate`. */
    fun attach(activity: ComponentActivity) {
        permissionLauncher = activity.registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            pendingPermission?.complete(granted)
            pendingPermission = null
        }
        screenLauncher = activity.registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            pendingScreen?.complete(result.data.takeIf { result.resultCode == android.app.Activity.RESULT_OK })
            pendingScreen = null
        }
    }

    fun detach() {
        permissionLauncher = null
        screenLauncher = null
        pendingPermission?.complete(false)
        pendingScreen?.complete(null)
        pendingPermission = null
        pendingScreen = null
    }

    fun granted(permission: String): Boolean {
        val app = context ?: return false
        return ContextCompat.checkSelfPermission(app, permission) == PackageManager.PERMISSION_GRANTED
    }

    /** Есть разрешение — сразу `true`; иначе спросить. */
    suspend fun ensure(permission: String): Boolean {
        val name = permission.substringAfterLast('.')
        if (granted(permission)) return true
        val launcher = permissionLauncher
        if (launcher == null) {
            CallLog.warning("Разрешение $name: нет окна, чтобы спросить — считаю, что нет")
            return false
        }
        pendingPermission?.complete(false)
        val answer = CompletableDeferred<Boolean>()
        pendingPermission = answer
        CallLog.info("Разрешение $name: спрашиваю")
        try {
            launcher.launch(permission)
        } catch (e: Exception) {
            CallLog.error("Разрешение $name: запрос не открылся", e)
            pendingPermission = null
            return false
        }
        return answer.await().also { CallLog.info("Разрешение $name: ${if (it) "дано" else "не дано"}") }
    }

    /** Системный запрос на показ экрана: данные для MediaProjection или `null`, если отказали. */
    suspend fun screenCapture(): Intent? {
        val app = context ?: return null
        val launcher = screenLauncher ?: return null
        val manager = app.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        pendingScreen?.complete(null)
        val answer = CompletableDeferred<Intent?>()
        pendingScreen = answer
        try {
            launcher.launch(manager.createScreenCaptureIntent())
        } catch (e: Exception) {
            CallLog.error("Показ экрана: запрос не открылся", e)
            pendingScreen = null
            return null
        }
        return answer.await().also { CallLog.info("Показ экрана: ${if (it != null) "разрешён" else "отказано"}") }
    }
}
