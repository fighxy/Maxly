package app.maxly

import android.app.Application
import app.maxly.diagnostics.Diagnostics
import com.max.shared.PlatformSession
import com.max.shared.init
import kotlinx.coroutines.launch

class MaxlyApp : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        // Журнал и отчёты о сбоях — раньше всего остального, чтобы поймать и сбой запуска.
        Diagnostics.init(this)
        // Ядру нужен контекст для хранилища токена до создания клиента.
        PlatformSession.init(this)
        container = AppContainer(this)
        container.scope.launch { container.session.restoreSession() }
    }
}
