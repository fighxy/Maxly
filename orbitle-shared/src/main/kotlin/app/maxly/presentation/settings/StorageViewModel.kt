package app.maxly.presentation.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.maxly.data.StorageRepository
import app.maxly.domain.StorageCategory
import app.maxly.domain.StorageUsage
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.Locale

/** «Данные и память»: размер кэша по категориям и очистка отмеченных. */
class StorageViewModel(private val storage: StorageRepository) : ViewModel() {

    data class State(
        /** `null`, пока размеры считаются. */
        val usage: StorageUsage? = null,
        /** По умолчанию отмечено всё. */
        val selection: Set<StorageCategory> = StorageCategory.entries.toSet(),
        val clearing: Boolean = false,
    ) {
        val selectedBytes: Long get() = usage?.let { u -> selection.sumOf { u.of(it) } } ?: 0L

        /** Доля категории в общем размере, 0…1. */
        fun share(category: StorageCategory): Float {
            val u = usage ?: return 0f
            return if (u.total <= 0) 0f else u.of(category).toFloat() / u.total
        }
    }

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    init {
        load()
    }

    fun load() {
        viewModelScope.launch {
            val usage = runCatchingUsage() ?: StorageUsage(emptyMap())
            _state.update { it.copy(usage = usage) }
        }
    }

    fun toggle(category: StorageCategory) = _state.update {
        it.copy(selection = if (category in it.selection) it.selection - category else it.selection + category)
    }

    fun clearSelected() {
        val chosen = _state.value.selection
        if (chosen.isEmpty() || _state.value.clearing) return
        _state.update { it.copy(clearing = true) }
        viewModelScope.launch {
            try {
                storage.clear(chosen)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                // Что удалилось — удалилось; новые размеры покажут остальное.
            }
            val usage = runCatchingUsage() ?: _state.value.usage
            _state.update { it.copy(usage = usage, clearing = false) }
        }
    }

    private suspend fun runCatchingUsage(): StorageUsage? = try {
        storage.usage()
    } catch (e: CancellationException) {
        throw e
    } catch (_: Exception) {
        null
    }

    companion object {
        /** `0 Б`, `512 КБ`, `1,2 МБ`, `3,4 ГБ`. */
        fun format(bytes: Long): String {
            val units = listOf("Б", "КБ", "МБ", "ГБ", "ТБ")
            var value = bytes.coerceAtLeast(0).toDouble()
            var unit = 0
            while (value >= 1024 && unit < units.lastIndex) {
                value /= 1024
                unit++
            }
            val number = if (unit == 0 || value >= 100) String.format(Locale.ROOT, "%.0f", value)
            else String.format(Locale.ROOT, "%.1f", value).removeSuffix(".0").replace('.', ',')
            return "$number ${units[unit]}"
        }
    }
}
