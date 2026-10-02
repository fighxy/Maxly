package app.orbitle

import android.app.Application
import com.max.shared.PlatformSession
import com.max.shared.init
import kotlinx.coroutines.launch

class OrbitleApp : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        // Ядру нужен контекст для хранилища токена до создания клиента.
        PlatformSession.init(this)
        container = AppContainer(this)
        container.scope.launch { container.session.restoreSession() }
    }
}
