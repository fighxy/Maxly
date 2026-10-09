package app.orbitle.diagnostics

import java.lang.management.ManagementFactory
import java.lang.management.ThreadInfo

/**
 * Стеки всех потоков текстом, поток окна (AWT-EventQueue) первым. С `java.management`
 * видно ещё, какой монитор поток ждёт и кто его держит — этого хватает, чтобы найти взаимную
 * блокировку. Без модуля — стеки и состояния из [Thread.getAllStackTraces].
 */
object ThreadDump {
    private const val UI_THREAD = "AWT-EventQueue"

    fun capture(): String = try {
        fromManagement()
    } catch (_: Throwable) {
        fromThreads()
    }

    private fun fromManagement(): String {
        val bean = ManagementFactory.getThreadMXBean()
        val infos = bean.dumpAllThreads(bean.isObjectMonitorUsageSupported, bean.isSynchronizerUsageSupported)
        val deadlocked = runCatching { bean.findDeadlockedThreads() }.getOrNull()?.toSet().orEmpty()
        return buildString {
            if (deadlocked.isNotEmpty()) {
                append("Взаимная блокировка потоков: ").append(infos.filter { it.threadId in deadlocked }.joinToString { it.threadName }).append("\n\n")
            }
            infos.sortedWith(uiFirst { it.threadName }).forEach { append(format(it)).append('\n') }
        }
    }

    private fun fromThreads(): String = buildString {
        Thread.getAllStackTraces().entries.sortedWith(uiFirst { it.key.name }).forEach { (thread, frames) ->
            append('"').append(thread.name).append("\" ").append(thread.state)
            if (thread.isDaemon) append(" daemon")
            append('\n')
            frames.forEach { append("    at ").append(it).append('\n') }
            append('\n')
        }
    }

    /** Как [ThreadInfo.toString], но без обрезки стека до восьми строк. */
    fun format(info: ThreadInfo): String = buildString {
        append('"').append(info.threadName).append("\" #").append(info.threadId).append(' ').append(info.threadState)
        if (info.isDaemon) append(" daemon")
        info.lockName?.let { append(" on ").append(it) }
        info.lockOwnerName?.let { append(" owned by \"").append(it).append("\" #").append(info.lockOwnerId) }
        if (info.isSuspended) append(" (suspended)")
        if (info.isInNative) append(" (in native)")
        append('\n')
        val monitors = info.lockedMonitors.orEmpty()
        info.stackTrace.forEachIndexed { depth, frame ->
            append("    at ").append(frame).append('\n')
            if (depth == 0) info.lockInfo?.let { lock ->
                val verb = when (info.threadState) {
                    Thread.State.BLOCKED -> "blocked on"
                    Thread.State.WAITING, Thread.State.TIMED_WAITING -> "waiting on"
                    else -> null
                }
                if (verb != null) append("    - ").append(verb).append(' ').append(lock).append('\n')
            }
            monitors.filter { it.lockedStackDepth == depth }.forEach { append("    - locked ").append(it).append('\n') }
        }
        val synchronizers = info.lockedSynchronizers.orEmpty()
        if (synchronizers.isNotEmpty()) {
            append("    Locked synchronizers:\n")
            synchronizers.forEach { append("    - ").append(it).append('\n') }
        }
    }

    private fun <T> uiFirst(name: (T) -> String): Comparator<T> =
        compareBy<T> { if (name(it).startsWith(UI_THREAD)) 0 else 1 }.thenBy { name(it) }
}
