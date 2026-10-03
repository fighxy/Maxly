package app.orbitle.presentation.settings

import app.orbitle.MainDispatcherRule
import app.orbitle.data.AccountRepository
import app.orbitle.domain.Account
import app.orbitle.domain.AccountSettings
import app.orbitle.domain.BlockedUser
import app.orbitle.domain.MiniApp
import app.orbitle.domain.OrbitleError
import app.orbitle.domain.PrivacyChange
import app.orbitle.domain.TwoFactorStatus
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class MiniAppTest {
    private val bridge = MiniAppBridge()

    @get:Rule val main = MainDispatcherRule()

    @Test
    fun `external callback is only externalCallback=1`() {
        assertTrue(MiniApp.isExternalCallback("https://digital-id.max.ru/cb?externalCallback=1&code=x"))
        assertFalse(MiniApp.isExternalCallback("https://digital-id.max.ru/cb?externalCallback=0"))
        assertFalse(MiniApp.isExternalCallback("https://gosuslugi.ru/"))
        assertTrue(MiniApp.isExternalCallback("https://digital-id.max.ru/cb?externalCallback=1#later"))
        assertTrue(MiniApp.opensExternally("max://chat"))
        assertFalse(MiniApp.opensExternally("https://max.ru"))
        assertFalse(MiniApp.opensExternally("about:blank"))
    }

    @Test
    fun `launch context and viewport answer with requestId`() {
        assertEquals(
            listOf(MiniAppBridge.Action.Reply("WebAppGetLaunchContext", """{"entryPoint":"settings","requestId":"r1"}""")),
            bridge.handle("WebAppGetLaunchContext", """{"requestId":"r1"}""", 390, 700),
        )
        assertEquals(
            listOf(MiniAppBridge.Action.Reply("WebAppGetViewportSize", """{"height":700,"isStateStable":true,"width":390}""")),
            bridge.handle("WebAppGetViewportSize", null, 390, 700),
        )
    }

    @Test
    fun `back button, closing confirmation, links and close`() {
        assertEquals(
            listOf(MiniAppBridge.Action.BackButton(true)),
            bridge.handle("WebAppSetupBackButton", """{"isVisible":true}""", 390, 700),
        )
        assertEquals(
            listOf(MiniAppBridge.Action.ClosingConfirmation(true)),
            bridge.handle("WebAppSetupClosingBehavior", """{"needConfirmation":true}""", 390, 700),
        )
        assertEquals(
            listOf(MiniAppBridge.Action.OpenLink("https://max.ru")),
            bridge.handle("WebAppOpenLink", """{"url":"https://max.ru"}""", 390, 700),
        )
        assertEquals(listOf(MiniAppBridge.Action.Close), bridge.handle("WebAppClose", null, 390, 700))
    }

    @Test
    fun `unknown method with requestId gets client method unsupported`() {
        assertEquals(
            listOf(MiniAppBridge.Action.Reply(
                "WebAppRequestPhone",
                """{"error":{"code":"client.request_phone.unsupported"},"requestId":"7"}""",
            )),
            bridge.handle("WebAppRequestPhone", """{"requestId":"7"}""", 390, 700),
        )
        assertEquals(listOf(MiniAppBridge.Action.Ignore), bridge.handle("WebAppRequestPhone", null, 390, 700))
        assertEquals("biometry_get_info", bridge.slug("WebAppBiometryGetInfo"))
        assertEquals(emptyList<MiniAppBridge.Action>(), bridge.handle("WebAppReady", "{", 390, 700))
    }

    @Test
    fun `share joins text and link`() {
        assertEquals(
            listOf(MiniAppBridge.Action.Share("Привет\nhttps://max.ru", "s")),
            bridge.handle("WebAppShare", """{"text":"Привет","link":"https://max.ru","requestId":"s"}""", 390, 700),
        )
        assertEquals(
            MiniAppBridge.Action.Reply("WebAppShare", """{"requestId":"s","status":"shared"}"""),
            bridge.shareFinished("s", completed = true),
        )
        assertEquals(
            MiniAppBridge.Action.Reply("WebAppShare", """{"requestId":"s","status":"cancelled"}"""),
            bridge.shareFinished("s", completed = false),
        )
        assertEquals(
            listOf(MiniAppBridge.Action.Reply("WebAppShare", """{"error":{"code":"client.share.invalid_request"},"requestId":"s"}""")),
            bridge.handle("WebAppShare", """{"requestId":"s"}""", 390, 700),
        )
    }

    @Test
    fun `haptic status uses the iphone spelling`() {
        assertEquals(
            listOf(
                MiniAppBridge.Action.Haptic(MiniAppBridge.HapticKind.Impact("light")),
                MiniAppBridge.Action.Reply("WebAppHapticFeedbackImpact", """{"status":"impactOccured"}"""),
            ),
            bridge.handle("WebAppHapticFeedbackImpact", null, 390, 700),
        )
        assertEquals(MiniAppBridge.Action.Reply("WebAppBackButtonPressed", "{}"), bridge.backPressed)
    }

    @Test
    fun `nfc info and screen capture are local replies`() {
        assertEquals(
            listOf(MiniAppBridge.Action.Reply("WebAppNfcGetInfo", """{"available":false,"enabled":false,"requestId":"n"}""")),
            bridge.handle("WebAppNfcGetInfo", """{"requestId":"n"}""", 390, 700),
        )
        assertEquals(
            listOf(MiniAppBridge.Action.Reply(
                "WebAppSetupScreenCaptureBehavior",
                """{"isScreenCaptureEnabled":true,"requestId":"c"}""",
            )),
            bridge.handle("WebAppSetupScreenCaptureBehavior", """{"isScreenCaptureEnabled":true,"requestId":"c"}""", 390, 700),
        )
    }

    @Test
    fun `digital id biometry answers locally and keeps the session device`() {
        val bridge = MiniAppBridge(botId = 8250447, deviceId = "dev1", vault = MiniAppVault.memory())
        assertEquals(
            listOf(MiniAppBridge.Action.Reply(
                "WebAppBiometryGetInfo",
                """{"accessGranted":false,"accessRequested":false,"available":true,"deviceId":"dev1","requestId":"b","tokenSaved":false,"type":["unknown"]}""",
            )),
            bridge.handle("WebAppBiometryGetInfo", """{"requestId":"b"}""", 390, 700),
        )
        assertEquals(
            listOf(MiniAppBridge.Action.Reply("WebAppBiometryUpdateToken", """{"requestId":"u","status":"updated"}""")),
            bridge.handle("WebAppBiometryUpdateToken", """{"token":"t1","requestId":"u"}""", 390, 700),
        )
        assertEquals(
            listOf(MiniAppBridge.Action.Reply(
                "WebAppBiometryGetInfo",
                """{"accessGranted":true,"accessRequested":true,"available":true,"deviceId":"dev1","requestId":"b","tokenSaved":true,"type":["unknown"]}""",
            )),
            bridge.handle("WebAppBiometryGetInfo", """{"requestId":"b"}""", 390, 700),
        )
        val auth = bridge.handle("WebAppBiometryRequestAuth", """{"requestId":"a"}""", 390, 700).single() as MiniAppBridge.Action.Reply
        val body = Json.parseToJsonElement(auth.json).jsonObject
        assertEquals("t1", body.getValue("token").jsonPrimitive.content)
        assertEquals("authorized", body.getValue("status").jsonPrimitive.content)
        assertEquals(
            listOf(MiniAppBridge.Action.Reply(
                "WebAppSecureStorageGetKey",
                """{"error":{"code":"client.secure_storage_get_key.not_found"},"requestId":"k"}""",
            )),
            bridge.handle("WebAppSecureStorageGetKey", """{"key":"pin","requestId":"k"}""", 390, 700),
        )
        assertEquals(
            listOf(MiniAppBridge.Action.Reply("WebAppSecureStorageSaveKey", """{"requestId":"k","status":"saved"}""")),
            bridge.handle("WebAppSecureStorageSaveKey", """{"key":"pin","value":"salt","requestId":"k"}""", 390, 700),
        )
        assertEquals(
            listOf(MiniAppBridge.Action.Reply("WebAppSecureStorageGetKey", """{"key":"pin","requestId":"k","value":"salt"}""")),
            bridge.handle("WebAppSecureStorageGetKey", """{"key":"pin","requestId":"k"}""", 390, 700),
        )
    }

    @Test
    fun `launch opens the app and a callback replaces it`() {
        val repo = MiniAccount()
        val model = MiniAppViewModel(MiniApp.Kind.DIGITAL_ID, repo)
        model.launch()
        val ready = model.state.value.phase as MiniAppViewModel.Phase.Ready
        assertEquals(8250447L, ready.app.botId)
        assertEquals("https://id.example/start", ready.app.url)
        assertEquals("Цифровой ID", model.title)
        model.handleCallback("https://digital-id.max.ru/cb?externalCallback=1")
        val next = model.state.value.phase as MiniAppViewModel.Phase.Ready
        assertEquals("https://id.example/back", next.app.url)
        assertEquals(listOf("https://digital-id.max.ru/cb?externalCallback=1"), repo.callbacks)
        repo.failure = OrbitleError.NetworkUnavailable
        model.launch()
        val failed = model.state.value.phase as MiniAppViewModel.Phase.Failed
        assertEquals("Нет соединения с сервером", failed.message)
        assertNull((model.state.value.phase as? MiniAppViewModel.Phase.Ready))
    }
}

/** Аккаунт только для мини-приложения: остальное не используется. */
private class MiniAccount : AccountRepository {
    override val account = MutableStateFlow<Account?>(null)
    override val settings = MutableStateFlow(AccountSettings())
    var failure: OrbitleError? = null
    val callbacks = mutableListOf<String>()

    override suspend fun reload() = Unit
    override suspend fun updateProfile(firstName: String, lastName: String, about: String) = Unit
    override suspend fun uploadAvatar(jpeg: ByteArray) = Unit
    override suspend fun removeAvatar() = Unit
    override suspend fun requestDeletion(): Long? = null
    override suspend fun change(change: PrivacyChange): AccountSettings = settings.value
    override suspend fun blockedUsers(): List<BlockedUser> = emptyList()
    override suspend fun unblock(userId: String) = Unit
    override suspend fun twoFactorStatus(): TwoFactorStatus = TwoFactorStatus(false)
    override suspend fun startEmailChange(password: String): String = "track"
    override suspend fun sendEmailCode(trackId: String, email: String): Int = 60
    override suspend fun confirmEmail(trackId: String, code: String): TwoFactorStatus = TwoFactorStatus(true)

    override suspend fun launchMiniApp(kind: MiniApp.Kind): MiniApp {
        failure?.let { throw it }
        val bot = if (kind == MiniApp.Kind.SFERUM) 2340831L else 8250447L
        return MiniApp(bot, "https://id.example/start", "q")
    }

    override suspend fun miniAppCallback(url: String): MiniApp {
        failure?.let { throw it }
        callbacks += url
        return MiniApp(8250447L, "https://id.example/back", "q2")
    }
}
