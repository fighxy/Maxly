package app.maxly.platform

import app.maxly.data.PreferenceStore

/** Место окна в dp: левый верхний угол, размер и развёрнуто ли оно на весь экран. */
data class WindowBounds(val x: Int, val y: Int, val width: Int, val height: Int, val maximized: Boolean = false)

/** Прямоугольник экрана в тех же единицах, что и окно. */
data class ScreenArea(val x: Int, val y: Int, val width: Int, val height: Int)

/** Где открыть окно: [x]/[y] `null` — по центру экрана. */
data class WindowStart(val x: Int?, val y: Int?, val width: Int, val height: Int, val maximized: Boolean)

/**
 * Окно открывается там, где его закрыли. Если сохранённого места нет или его экран отключили,
 * окно встаёт по центру; размер не меньше минимального и не больше самого большого экрана.
 */
object WindowPlacement {
    const val DEFAULT_WIDTH = 1100
    const val DEFAULT_HEIGHT = 760
    const val MIN_WIDTH = 840
    const val MIN_HEIGHT = 600

    /** Сколько заголовка окна должно оставаться на экране, чтобы за него можно было взяться мышью. */
    private const val GRIP_WIDTH = 120
    private const val GRIP_HEIGHT = 32

    fun start(saved: WindowBounds?, screens: List<ScreenArea>): WindowStart {
        val maxWidth = screens.maxOfOrNull { it.width } ?: Int.MAX_VALUE
        val maxHeight = screens.maxOfOrNull { it.height } ?: Int.MAX_VALUE
        fun clampWidth(value: Int) = value.coerceAtMost(maxWidth).coerceAtLeast(MIN_WIDTH)
        fun clampHeight(value: Int) = value.coerceAtMost(maxHeight).coerceAtLeast(MIN_HEIGHT)
        if (saved == null) {
            return WindowStart(null, null, clampWidth(DEFAULT_WIDTH), clampHeight(DEFAULT_HEIGHT), maximized = false)
        }
        val width = clampWidth(saved.width)
        val height = clampHeight(saved.height)
        val reachable = screens.any { titleBarVisible(saved.x, saved.y, width, it) }
        return if (reachable) {
            WindowStart(saved.x, saved.y, width, height, saved.maximized)
        } else {
            WindowStart(null, null, width, height, saved.maximized)
        }
    }

    private fun titleBarVisible(x: Int, y: Int, width: Int, screen: ScreenArea): Boolean {
        val left = maxOf(x, screen.x)
        val right = minOf(x + width, screen.x + screen.width)
        val top = maxOf(y, screen.y)
        val bottom = minOf(y + GRIP_HEIGHT, screen.y + screen.height)
        return right - left >= GRIP_WIDTH && bottom - top >= GRIP_HEIGHT / 2
    }

    /** Экраны компьютера в единицах окна (на Windows с масштабом — уже поделённые на него). */
    fun screens(): List<ScreenArea> = runCatching {
        java.awt.GraphicsEnvironment.getLocalGraphicsEnvironment().screenDevices.map {
            val bounds = it.defaultConfiguration.bounds
            ScreenArea(bounds.x, bounds.y, bounds.width, bounds.height)
        }
    }.getOrDefault(emptyList())
}

/** Место окна в настройках: строка `x,y,ширина,высота,развёрнуто`. */
class WindowPlacementStore(private val store: PreferenceStore) {
    fun load(): WindowBounds? = decode(store.get(KEY))

    fun save(bounds: WindowBounds) = store.put(KEY, encode(bounds))

    companion object {
        private const val KEY = "window.bounds"

        fun encode(bounds: WindowBounds): String =
            listOf(bounds.x, bounds.y, bounds.width, bounds.height, if (bounds.maximized) 1 else 0).joinToString(",")

        fun decode(raw: String?): WindowBounds? {
            val parts = raw?.split(',')?.map { it.trim().toIntOrNull() } ?: return null
            if (parts.size != 5 || parts.any { it == null }) return null
            val (x, y, width, height) = parts.map { it!! }
            if (width <= 0 || height <= 0) return null
            return WindowBounds(x, y, width, height, parts[4] == 1)
        }
    }
}
