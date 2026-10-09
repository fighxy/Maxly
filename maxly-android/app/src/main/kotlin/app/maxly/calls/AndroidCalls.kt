package app.maxly.calls

import android.Manifest
import android.content.Context
import android.content.Intent
import app.maxly.AppContainer
import app.maxly.presentation.calls.CallPeerInfo
import kotlinx.coroutines.launch

/** Звонки из приложения: сначала микрофон, как на iOS; без него звонок не начинается. */
object AndroidCalls {
    fun start(container: AppContainer, peer: CallPeerInfo, video: Boolean) {
        container.scope.launch {
            if (!microphone(container)) return@launch
            container.callCenter.startCall(peer, video)
        }
    }

    fun join(container: AppContainer, link: String) {
        container.scope.launch {
            if (!microphone(container)) return@launch
            container.callCenter.join(link)
        }
    }

    /** Ответить на входящий; без микрофона он отклоняется. */
    fun answer(container: AppContainer, video: Boolean) {
        container.scope.launch {
            if (!microphone(container)) {
                container.callCenter.decline()
                return@launch
            }
            container.callCenter.answer(video)
        }
    }

    /** Поделиться ссылкой на звонок через системный лист. */
    fun share(context: Context, link: String) {
        val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, link)
        context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    private suspend fun microphone(container: AppContainer): Boolean {
        if (CallPermissions.ensure(Manifest.permission.RECORD_AUDIO)) return true
        container.callCenter.showError(CallPermissions.MICROPHONE_DENIED)
        return false
    }
}
