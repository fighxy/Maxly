package app.maxly.ui.settings

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.ContextCompat
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.qrcode.QRCodeReader
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Полноэкранный сканер QR-кода: камера сзади, только QR. Первое распознанное значение уходит
 * в [onResult]; без доступа к камере — [onDenied].
 */
@Composable
fun QrScannerDialog(onResult: (String) -> Unit, onDenied: () -> Unit, onDismiss: () -> Unit) {
    val context = LocalContext.current
    var granted by remember {
        mutableStateOf(ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED)
    }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        granted = it
        if (!it) onDenied()
    }
    LaunchedEffect(Unit) { if (!granted) permission.launch(Manifest.permission.CAMERA) }
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            if (granted) CameraPreview(onResult)
            Box(Modifier.align(Alignment.Center).size(240.dp).border(3.dp, Color.White, RoundedCornerShape(24.dp)))
            Column(Modifier.align(Alignment.BottomCenter).padding(32.dp)) {
                Text(
                    "Наведите камеру на QR-код входа",
                    color = Color.White,
                    textAlign = TextAlign.Center,
                )
            }
            IconButton(onClick = onDismiss, modifier = Modifier.statusBarsPadding().padding(8.dp)) {
                Icon(Icons.Filled.Close, "Закрыть", tint = Color.White)
            }
        }
    }
}

@Composable
private fun CameraPreview(onResult: (String) -> Unit) {
    val context = LocalContext.current
    val owner = LocalLifecycleOwner.current
    val result by rememberUpdatedState(onResult)
    val executor = remember { Executors.newSingleThreadExecutor() }
    val done = remember { AtomicBoolean(false) }
    val preview = remember { PreviewView(context) }
    DisposableEffect(owner) {
        val future = ProcessCameraProvider.getInstance(context)
        future.addListener({
            val provider = future.get()
            val shown = Preview.Builder().build().also { it.surfaceProvider = preview.surfaceProvider }
            val analysis = ImageAnalysis.Builder().setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).build()
            val reader = QRCodeReader()
            val hints = mapOf(DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE), DecodeHintType.TRY_HARDER to true)
            analysis.setAnalyzer(executor) { image ->
                val text = if (done.get()) null else decode(image, reader, hints)
                image.close()
                if (text != null && done.compareAndSet(false, true)) {
                    ContextCompat.getMainExecutor(context).execute { result(text) }
                }
            }
            runCatching {
                provider.unbindAll()
                provider.bindToLifecycle(owner, CameraSelector.DEFAULT_BACK_CAMERA, shown, analysis)
            }
        }, ContextCompat.getMainExecutor(context))
        onDispose {
            runCatching { future.get().unbindAll() }
            executor.shutdown()
        }
    }
    AndroidView({ preview }, Modifier.fillMaxSize())
}

/** Яркость кадра (плоскость Y) → ZXing. Строки кадра бывают шире картинки: учитывается шаг. */
private fun decode(image: ImageProxy, reader: QRCodeReader, hints: Map<DecodeHintType, Any>): String? {
    val plane = image.planes.firstOrNull() ?: return null
    val buffer = plane.buffer
    val stride = plane.rowStride
    val data = ByteArray(stride * image.height)
    buffer.rewind()
    buffer.get(data, 0, minOf(buffer.remaining(), data.size))
    return try {
        val source = PlanarYUVLuminanceSource(data, stride, image.height, 0, 0, image.width, image.height, false)
        reader.decode(BinaryBitmap(HybridBinarizer(source)), hints).text
    } catch (e: Exception) {
        null
    } finally {
        reader.reset()
    }
}
