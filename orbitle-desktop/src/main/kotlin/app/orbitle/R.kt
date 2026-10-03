package app.orbitle

/** Идентификаторы строк и картинок. Тексты лежат в [STRING_TABLE], файлы — в [DRAWABLE_FILES]. */
object R {
    object string {
        const val app_name = 1
        const val tab_chats = 2
        const val tab_calls = 3
        const val tab_contacts = 4
        const val tab_settings = 5
        const val auth_welcome_title = 6
        const val auth_welcome_subtitle = 7
        const val auth_country = 8
        const val auth_country_code = 9
        const val auth_phone = 10
        const val auth_next = 11
        const val auth_session_expired = 12
        const val auth_code_label = 13
        const val auth_verify = 14
        const val auth_change_number = 15
        const val auth_password_label = 16
        const val auth_sign_in = 17
        const val auth_first_name = 18
        const val auth_last_name = 19
        const val auth_register_prompt = 20
        const val auth_create_account = 21
        const val auth_back = 22
        const val auth_show_password = 23
        const val auth_hide_password = 24
        const val country_picker_title = 25
        const val country_search = 26
        const val country_not_found = 27
        const val chats_title = 28
        const val chats_search = 29
        const val chats_empty = 30
        const val chats_empty_hint = 31
        const val chats_search_empty = 32
        const val chats_search_global = 33
        const val chats_search_messages = 34
        const val chats_offline = 35
        const val chats_retry = 36
        const val chats_pin = 37
        const val chats_unpin = 38
        const val chats_pinned = 39
        const val chats_muted = 40
        const val chats_verified = 41
        const val chats_draft = 42
        const val chats_close_search = 43
        const val calls_title = 44
        const val contacts_title = 45
        const val soon = 46
        const val settings_title = 47
        const val settings_about = 48
        const val settings_logout = 49
        const val settings_logout_confirm_title = 50
        const val settings_logout_confirm_text = 51
        const val settings_cancel = 52
        const val about_version = 53
        const val about_build = 54
        const val about_core = 55
        const val about_text = 56
        const val about_source = 57
    }

    object drawable {
        const val orbitle_mark = 1001
        const val splash_mark = 1002
        const val wallpaper_autumn = 1003
        const val wallpaper_autumn_thumb = 1004
        const val wallpaper_autumn_dark = 1005
        const val wallpaper_autumn_dark_thumb = 1006
        const val wallpaper_autumn_night = 1007
        const val wallpaper_autumn_night_thumb = 1008
    }
}

internal val STRING_TABLE: Map<Int, String> = mapOf(
    R.string.app_name to "Orbitle",
    R.string.tab_chats to "Чаты",
    R.string.tab_calls to "Звонки",
    R.string.tab_contacts to "Контакты",
    R.string.tab_settings to "Настройки",
    R.string.auth_welcome_title to "Orbitle",
    R.string.auth_welcome_subtitle to "Мессенджер для Max. Введите номер телефона, чтобы войти",
    R.string.auth_country to "Страна",
    R.string.auth_country_code to "Код",
    R.string.auth_phone to "Номер телефона",
    R.string.auth_next to "Далее",
    R.string.auth_session_expired to "Сессия истекла. Войдите снова",
    R.string.auth_code_label to "Код",
    R.string.auth_verify to "Подтвердить",
    R.string.auth_change_number to "Изменить номер",
    R.string.auth_password_label to "Облачный пароль",
    R.string.auth_sign_in to "Войти",
    R.string.auth_first_name to "Имя",
    R.string.auth_last_name to "Фамилия (необязательно)",
    R.string.auth_register_prompt to "Номер ещё не зарегистрирован. Как вас зовут?",
    R.string.auth_create_account to "Создать аккаунт",
    R.string.auth_back to "Назад",
    R.string.auth_show_password to "Показать пароль",
    R.string.auth_hide_password to "Скрыть пароль",
    R.string.country_picker_title to "Выберите страну",
    R.string.country_search to "Поиск страны",
    R.string.country_not_found to "Ничего не нашлось",
    R.string.chats_title to "Чаты",
    R.string.chats_search to "Поиск",
    R.string.chats_empty to "Пока нет чатов",
    R.string.chats_empty_hint to "Начните переписку из контактов",
    R.string.chats_search_empty to "Ничего не найдено",
    R.string.chats_search_global to "Глобальный поиск",
    R.string.chats_search_messages to "Сообщения",
    R.string.chats_offline to "Нет соединения с сервером",
    R.string.chats_retry to "Повторить",
    R.string.chats_pin to "Закрепить",
    R.string.chats_unpin to "Открепить",
    R.string.chats_pinned to "Закреплён",
    R.string.chats_muted to "Без звука",
    R.string.chats_verified to "Подтверждённый",
    R.string.chats_draft to "Черновик:",
    R.string.chats_close_search to "Закрыть поиск",
    R.string.calls_title to "Звонки",
    R.string.contacts_title to "Контакты",
    R.string.soon to "Скоро здесь появится",
    R.string.settings_title to "Настройки",
    R.string.settings_about to "О приложении",
    R.string.settings_logout to "Выйти",
    R.string.settings_logout_confirm_title to "Выйти из аккаунта?",
    R.string.settings_logout_confirm_text to "Чтобы вернуться, понадобится код из SMS",
    R.string.settings_cancel to "Отмена",
    R.string.about_version to "Версия",
    R.string.about_build to "Сборка",
    R.string.about_core to "Ядро max-kmp-core",
    R.string.about_text to "Неофициальный клиент Max для компьютера. Работает на открытом ядре max-kmp-core и представляется сервису как Android-устройство.",
    R.string.about_source to "Исходный код",
)

internal val DRAWABLE_FILES: Map<Int, String> = mapOf(
    R.drawable.orbitle_mark to "orbitle_mark.png",
    R.drawable.splash_mark to "splash_mark.png",
    R.drawable.wallpaper_autumn to "wallpaper_autumn.jpg",
    R.drawable.wallpaper_autumn_thumb to "wallpaper_autumn_thumb.jpg",
    R.drawable.wallpaper_autumn_dark to "wallpaper_autumn_dark.jpg",
    R.drawable.wallpaper_autumn_dark_thumb to "wallpaper_autumn_dark_thumb.jpg",
    R.drawable.wallpaper_autumn_night to "wallpaper_autumn_night.jpg",
    R.drawable.wallpaper_autumn_night_thumb to "wallpaper_autumn_night_thumb.jpg",
)
