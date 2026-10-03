package app.orbitle.presentation.settings

import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel

/** Ссылка на свой профиль, текст приглашения и QR-код — как в iOS-версии. */
object ProfileLink {
    /** Ссылка из конфига сервера (`invite-link`), иначе ссылка своего контакта. */
    fun link(inviteLink: String?, ownLink: String?): String? =
        inviteLink?.trim()?.takeIf { it.isNotEmpty() } ?: ownLink?.trim()?.takeIf { it.isNotEmpty() }

    fun inviteText(link: String): String = "Присоединяйся ко мне в MAX: $link"

    /**
     * Модули QR-кода: `true` — тёмный. Коррекция M, по краю тихая зона в [margin] модуля,
     * чтобы код читался и в тёмной теме (рисуется чёрным на белом).
     */
    fun qr(text: String, margin: Int = 2): List<BooleanArray> {
        val hints = mapOf(EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M, EncodeHintType.MARGIN to margin, EncodeHintType.CHARACTER_SET to "UTF-8")
        val matrix = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, 0, 0, hints)
        return List(matrix.height) { y -> BooleanArray(matrix.width) { x -> matrix.get(x, y) } }
    }
}
