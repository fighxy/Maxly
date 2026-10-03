package app.orbitle.ui.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import app.orbitle.platform.DesktopActions
import com.google.zxing.BinaryBitmap
import com.google.zxing.RGBLuminanceSource
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.qrcode.QRCodeReader
import java.io.File
import javax.imageio.ImageIO

/**
 * Вход по QR на компьютере: камеры нет, поэтому код вставляют текстом или открывают картинку.
 * [onDenied] остаётся в сигнатуре экрана устройств и здесь не вызывается.
 */
@Composable
fun QrScannerDialog(
    onResult: (String) -> Unit,
    @Suppress("UNUSED_PARAMETER") onDenied: () -> Unit,
    onDismiss: () -> Unit,
) {
    var text by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    Dialog(onDismissRequest = onDismiss) {
        Surface(shape = MaterialTheme.shapes.extraLarge) {
            Column(Modifier.padding(24.dp).widthIn(min = 420.dp, max = 520.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Войти по QR-коду", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                    IconButton(onClick = onDismiss) { Icon(Icons.Filled.Close, "Закрыть") }
                }
                Text(
                    "Вставьте ссылку из QR-кода или выберите картинку с кодом.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.height(12.dp))
                OutlinedTextField(
                    value = text,
                    onValueChange = {
                        text = it
                        error = null
                    },
                    label = { Text("Ссылка или текст кода") },
                    modifier = Modifier.fillMaxWidth(),
                    minLines = 3,
                )
                error?.let {
                    Spacer(Modifier.height(8.dp))
                    Text(it, color = MaterialTheme.colorScheme.error)
                }
                Spacer(Modifier.height(16.dp))
                Row {
                    OutlinedButton(onClick = {
                        val file = DesktopActions.pickFiles(imageOnly = true).firstOrNull()
                        if (file == null) return@OutlinedButton
                        val decoded = decodeQr(file)
                        if (decoded == null) error = "На картинке нет QR-кода" else onResult(decoded)
                    }) {
                        Icon(Icons.Outlined.Image, null, Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text("Из картинки")
                    }
                    Spacer(Modifier.weight(1f))
                    Button(onClick = {
                        val value = text.trim()
                        if (value.isEmpty()) error = "Вставьте текст кода" else onResult(value)
                    }) { Text("Продолжить") }
                }
            }
        }
    }
}

private fun decodeQr(file: File): String? = runCatching {
    val image = ImageIO.read(file) ?: return null
    val pixels = IntArray(image.width * image.height)
    image.getRGB(0, 0, image.width, image.height, pixels, 0, image.width)
    val source = RGBLuminanceSource(image.width, image.height, pixels)
    QRCodeReader().decode(BinaryBitmap(HybridBinarizer(source))).text
}.getOrNull()
