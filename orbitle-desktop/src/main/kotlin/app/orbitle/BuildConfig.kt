package app.orbitle

/** Сведения сборки для экрана «О приложении». Ревизия читается из core.lock при сборке не требуется: её пишет fetch. */
object BuildConfig {
    const val VERSION_NAME = "0.1.0"
    const val BUILD_SHA = "dev"
    const val CORE_REVISION = "56220c9"
}
