package app.maxly.notifications

import android.content.Context
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ProcessLifecycleOwner
import app.maxly.AppContainer
import app.maxly.domain.AuthPhase
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

/**
 * «Звонки и сообщения в фоне» на Android: служба [KeepAliveService], пока вошли и настройка
 * включена, и уведомления [MessageNotifier] о новых сообщениях, пока приложение свёрнуто.
 */
object BackgroundMessaging {
    fun start(context: Context, container: AppContainer) {
        val app = context.applicationContext
        val notifier = MessageNotifier(app)
        val foreground = ProcessLifecycleOwner.get().lifecycle.currentStateFlow
            .map { it.isAtLeast(Lifecycle.State.STARTED) }
            .distinctUntilChanged()
        container.scope.launch { foreground.collect(notifier::setAppActive) }
        container.scope.launch {
            container.incomingMessages.notices.collect { notifier.incoming(it, container.notificationSettings.enabled.value) }
        }
        container.scope.launch {
            combine(container.session.phase.map { it is AuthPhase.SignedIn }, container.notificationSettings.enabled, foreground) { signedIn, enabled, visible ->
                Triple(signedIn, enabled, visible)
            }.collect { (signedIn, enabled, visible) ->
                when {
                    !signedIn || !enabled -> KeepAliveService.stop(app)
                    // Из фона Android службу переднего плана не запускает: при следующем выходе на экран.
                    visible -> KeepAliveService.start(app)
                }
            }
        }
    }
}
