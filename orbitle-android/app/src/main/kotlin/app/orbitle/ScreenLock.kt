package app.orbitle

import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.PowerManager
import androidx.core.content.ContextCompat
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.distinctUntilChanged

/**
 * Экран включён и не заблокирован: `false` после выключения экрана и, пока виден экран блокировки,
 * после включения; `true` после разблокировки. Сначала — текущее состояние.
 */
fun screenUnlocked(context: Context): Flow<Boolean> = callbackFlow {
    val power = context.getSystemService(PowerManager::class.java)
    val keyguard = context.getSystemService(KeyguardManager::class.java)
    fun current(): Boolean = (power?.isInteractive ?: true) && keyguard?.isKeyguardLocked != true
    val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            trySend(if (intent.action == Intent.ACTION_SCREEN_OFF) false else current())
        }
    }
    val filter = IntentFilter().apply {
        addAction(Intent.ACTION_SCREEN_ON)
        addAction(Intent.ACTION_SCREEN_OFF)
        addAction(Intent.ACTION_USER_PRESENT)
    }
    ContextCompat.registerReceiver(context, receiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
    trySend(current())
    awaitClose { context.unregisterReceiver(receiver) }
}.distinctUntilChanged()
