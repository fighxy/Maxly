package app.orbitle.domain

/** Как можно удалить одно сообщение: у всех, только у себя или никак. */
enum class DeleteScope { ALL, SELF, NONE }

/**
 * Подтверждение удаления выбранного (план ядра `DeletePlan`, id — как у экрана): [scopes] по id;
 * [canDelete] — нет ни одного [DeleteScope.NONE] (и выбор не пуст); [showsForEveryone] — выбор
 * «у всех» (все [DeleteScope.ALL], не канал), он же включён сразу ([forEveryoneByDefault]);
 * [forcesForEveryone] — канал с правом удалять чужое: только у всех.
 */
data class DeletePlan(
    val scopes: Map<String, DeleteScope>,
    val canDelete: Boolean,
    val showsForEveryone: Boolean,
    val forEveryoneByDefault: Boolean,
    val forcesForEveryone: Boolean,
) {
    companion object {
        /** Удалить нельзя ничего. */
        val NONE = DeletePlan(emptyMap(), canDelete = false, showsForEveryone = false, forEveryoneByDefault = false, forcesForEveryone = false)
    }
}
