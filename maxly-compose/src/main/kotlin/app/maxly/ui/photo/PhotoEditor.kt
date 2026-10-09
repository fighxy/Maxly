package app.maxly.ui.photo

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import app.maxly.domain.OutgoingFile
import app.maxly.presentation.photo.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlin.math.min

/** Платформа декодирует/ориентирует фото один раз и рендерит копии вне UI-потока. */
interface PhotoEditorSource {
    val size: PhotoSize
    suspend fun preview(edits: List<PhotoEdit>): ImageBitmap
    suspend fun export(edits: List<PhotoEdit>): OutgoingFile
}

data class PhotoEditorSession(val original: OutgoingFile, val history: PhotoEditHistory)

private enum class Tool(val title: String) { CROP("Кадр"), ROTATE("Поворот"), DRAW("Рисунок"), TEXT("Текст"), FILTER("Фильтры") }
private val inkColors = listOf(0xffffffff.toInt(), 0xff111111.toInt(), 0xffef5350.toInt(), 0xffffca28.toInt(), 0xff66bb6a.toInt(), 0xff42a5f5.toInt())

@Composable
fun PhotoEditor(
    file: OutgoingFile,
    load: suspend (OutgoingFile) -> PhotoEditorSource,
    onClose: () -> Unit,
    session: PhotoEditorSession? = null,
    onSave: (OutgoingFile, PhotoEditorSession) -> Unit,
) {
    val sourceFile = session?.original ?: file
    var source by remember(file.path) { mutableStateOf<PhotoEditorSource?>(null) }
    var history by remember(file.path) { mutableStateOf(session?.history ?: PhotoEditHistory()) }
    var preview by remember(file.path) { mutableStateOf<ImageBitmap?>(null) }
    var tool by remember { mutableStateOf(Tool.CROP) }
    var crop by remember { mutableStateOf(PhotoCrop.FULL) }
    var cropStart by remember { mutableStateOf<PhotoPoint?>(null) }
    var points by remember { mutableStateOf<List<PhotoPoint>>(emptyList()) }
    var ink by remember { mutableIntStateOf(inkColors.first()) }
    var brush by remember { mutableFloatStateOf(.012f) }
    var textSize by remember { mutableFloatStateOf(.07f) }
    var text by remember { mutableStateOf("") }
    var filter by remember { mutableStateOf(PhotoFilter.MONO) }
    var amount by remember { mutableFloatStateOf(1f) }
    var filterPreview by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var rendering by remember { mutableStateOf(false) }
    var failure by remember { mutableStateOf<String?>(null) }
    var brushTool by remember { mutableStateOf(PhotoBrush.PEN) }
    var shape by remember { mutableStateOf<PhotoShape?>(null) }
    var filled by remember { mutableStateOf(false) }
    var cropDrag by remember { mutableStateOf<PhotoCropDrag?>(null) }
    var angle by remember { mutableFloatStateOf(0f) }
    var adjustments by remember { mutableStateOf(PhotoAdjustments()) }
    var tune by remember { mutableStateOf(PhotoTune.EXPOSURE) }
    var filterMode by remember { mutableIntStateOf(0) }
    var curveChannel by remember { mutableIntStateOf(0) }
    var selectedText by remember { mutableStateOf<PhotoEdit.Text?>(null) }
    var textStyle by remember { mutableStateOf(PhotoTextStyle.OUTLINE) }
    var textFont by remember { mutableStateOf(PhotoFont.SANS) }
    var textAlignment by remember { mutableStateOf(PhotoAlignment.LEFT) }
    var originalShown by remember { mutableStateOf(false) }
    var hexColor by remember { mutableStateOf("FFFFFF") }
    val scope = rememberCoroutineScope()
    val stagedText = selectedText?.takeIf { text.isNotBlank() }?.copy(text=text.trim(),color=ink,size=textSize,style=textStyle,font=textFont,alignment=textAlignment)
    val pending = buildList {
        if(tool == Tool.FILTER && filterPreview) add(PhotoEdit.Filter(filter,amount))
        if(tool == Tool.FILTER && !adjustments.isDefault) add(PhotoEdit.Adjust(adjustments))
        if(tool == Tool.ROTATE && angle != 0f) add(PhotoEdit.Straighten(angle))
        if(tool == Tool.TEXT && stagedText != null && stagedText != selectedText) add(PhotoEdit.ReplaceText(stagedText))
    }
    val displayedEdits = PhotoEditHistory(history.edits + pending).resolved
    val previewEdits = if(originalShown) emptyList() else displayedEdits
    val size = source?.let { history.size(it.size) }

    LaunchedEffect(file.path) {
        try { source = load(sourceFile) }
        catch (e: CancellationException) { throw e }
        catch (_: Exception) { failure = "Не удалось открыть фото" }
    }
    LaunchedEffect(source, previewEdits) {
        val loaded = source ?: return@LaunchedEffect
        rendering = true
        try { preview = loaded.preview(previewEdits) }
        catch (e: CancellationException) { throw e }
        catch (_: Exception) { failure = "Не удалось обработать фото. Отмените последнее действие и попробуйте снова." }
        finally { rendering = false }
    }

    fun commit(edit: PhotoEdit) { history = history.add(edit); points = emptyList(); cropStart = null }
    fun resetPending() { filterPreview=false; adjustments=PhotoAdjustments(); angle=0f; selectedText=null; text=""; crop=PhotoCrop.FULL; originalShown=false }
    fun selectText(item: PhotoEdit.Text) { selectedText=item; text=item.text; ink=item.color; textSize=item.size; textStyle=item.style; textFont=item.font; textAlignment=item.alignment }
    fun placeText(point: PhotoPoint) {
        if(text.isBlank()) return
        val selected = stagedText
        if(selected != null) {
            val position = source?.let { history.textPoint(selected.id,point,it.size) } ?: point
            val moved = selected.copy(point=position); commit(PhotoEdit.ReplaceText(moved)); selectText(moved)
        } else {
            val added = PhotoEdit.Text(text.trim(),point,ink,textSize,style=textStyle,font=textFont,alignment=textAlignment)
            commit(added); selectText(added)
        }
    }
    fun finish() {
        val loaded = source ?: return
        val extra = when {
            tool == Tool.CROP && crop != PhotoCrop.FULL -> listOf(PhotoEdit.Crop(crop))
            tool == Tool.TEXT && selectedText == null && text.isNotBlank() -> listOf(PhotoEdit.Text(text.trim(), PhotoPoint(.1f, .45f), ink, textSize,style=textStyle,font=textFont,alignment=textAlignment))
            else -> emptyList()
        }
        val finalHistory = PhotoEditHistory(history.edits + pending + extra)
        val finalEdits = finalHistory.resolved
        busy = true
        scope.launch {
            try { onSave(if (finalEdits.isEmpty()) sourceFile else loaded.export(finalEdits),PhotoEditorSession(sourceFile,finalHistory)) }
            catch (e: CancellationException) { throw e }
            catch (_: Exception) { failure = "Не удалось сохранить фото. Попробуйте ещё раз." }
            finally { busy = false }
        }
    }

    Dialog(onDismissRequest = { if (!busy) onClose() }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
            Column(Modifier.safeDrawingPadding().imePadding()) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    TextButton(onClick = onClose, enabled = !busy) { Text("Отмена") }
                    Text("Редактор фото", Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
                    TextButton(onClick = ::finish, enabled = source != null && !busy && !rendering && preview != null) { Text("Готово") }
                }
                Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 8.dp)) {
                    TextButton(onClick = { history = history.undo(); resetPending() }, enabled = history.edits.isNotEmpty() && !busy) { Text("Назад") }
                    TextButton(onClick = { history = history.redo(); resetPending() }, enabled = history.undone.isNotEmpty() && !busy) { Text("Повторить") }
                    TextButton(onClick = { history = PhotoEditHistory(); resetPending() }, enabled = !busy) { Text("Сбросить") }
                    TextButton(onClick = { originalShown = !originalShown }, enabled = !busy) { Text(if(originalShown) "Результат" else "Оригинал") }
                }
                BoxWithConstraints(Modifier.fillMaxWidth().weight(1f).background(Color.Black), contentAlignment = Alignment.Center) {
                    val image = preview
                    if (image != null && size != null) {
                        // Ввод ограничен самим фото, без полей вокруг него.
                        val ratio = image.width.toFloat() / image.height
                        val w = min(maxWidth.value, maxHeight.value * ratio)
                        val h = w / ratio
                        val canEdit = !busy && !rendering && !originalShown
                        Box(Modifier.size(w.dp, h.dp)) {
                            Image(image, "Редактируемое фото", Modifier.fillMaxSize(), contentScale = ContentScale.FillBounds)
                            Canvas(Modifier.fillMaxSize().pointerInput(tool, ink, brush, text, textSize, brushTool, shape, selectedText?.id, canEdit) {
                                fun point(offset: Offset) = PhotoPoint((offset.x / this.size.width).coerceIn(0f, 1f), (offset.y / this.size.height).coerceIn(0f, 1f))
                                if (canEdit && tool == Tool.TEXT) {
                                    detectDragGestures(onDragEnd = { points.lastOrNull()?.let(::placeText); points=emptyList() }, onDragStart = { points=listOf(point(it)) }, onDragCancel = { points=emptyList() }) { change,_ -> change.consume(); points=listOf(point(change.position)) }
                                } else if (canEdit && (tool == Tool.DRAW || tool == Tool.CROP)) {
                                    detectDragGestures(
                                        onDragStart = { offset -> if (tool == Tool.DRAW) points = listOf(point(offset)) else cropDrag = PhotoCropDrag(crop,point(offset),24.dp.toPx()/this.size.width,24.dp.toPx()/this.size.height) },
                                        onDragCancel = { points = emptyList(); cropStart = null },
                                        onDragEnd = {
                                            if(tool == Tool.DRAW && points.isNotEmpty()) {
                                                if(shape != null) PhotoCrop.between(points.first(),points.last())?.let { commit(PhotoEdit.Shape(it,shape!!,ink,brush,filled)) }
                                                else commit(PhotoEdit.Stroke(if(brushTool == PhotoBrush.ARROW) listOf(points.first(),points.last()) else points,ink,brush,brushTool))
                                            }
                                            points=emptyList(); cropDrag=null
                                        },
                                    ) { change, _ ->
                                        change.consume()
                                        val p = point(change.position)
                                        if (tool == Tool.DRAW) {
                                            val last = points.lastOrNull()
                                            if (last == null || kotlin.math.abs(last.x - p.x) + kotlin.math.abs(last.y - p.y) > .002f) points = points + p
                                        } else cropDrag?.let { crop=it.update(p) }
                                    }
                                }
                            }.pointerInput(tool,text,selectedText?.id,canEdit) {
                                if(canEdit && tool == Tool.TEXT) detectTapGestures { offset -> placeText(PhotoPoint((offset.x/this.size.width).coerceIn(0f,1f),(offset.y/this.size.height).coerceIn(0f,1f))) }
                            }) {
                                if (tool == Tool.CROP && !originalShown) {
                                    val l = crop.left * this.size.width; val t = crop.top * this.size.height
                                    val r = crop.right * this.size.width; val b = crop.bottom * this.size.height
                                    val shade = Color.Black.copy(alpha = .55f)
                                    drawRect(shade, size = Size(this.size.width, t))
                                    drawRect(shade, Offset(0f, b), Size(this.size.width, this.size.height - b))
                                    drawRect(shade, Offset(0f, t), Size(l, b - t))
                                    drawRect(shade, Offset(r, t), Size(this.size.width - r, b - t))
                                    drawRect(Color.White, Offset(l, t), Size(r - l, b - t), style = Stroke(2.dp.toPx()))
                                    listOf(Offset(l,t),Offset(r,t),Offset(l,b),Offset(r,b)).forEach { drawCircle(Color.White,4.dp.toPx(),it) }
                                    for (i in 1..2) {
                                        val x = l + (r - l) * i / 3; val y = t + (b - t) * i / 3
                                        drawLine(Color.White.copy(alpha = .5f), Offset(x, t), Offset(x, b))
                                        drawLine(Color.White.copy(alpha = .5f), Offset(l, y), Offset(r, y))
                                    }
                                }
                                if (points.isNotEmpty() && tool == Tool.DRAW) {
                                    val shapeRect = if(shape != null) PhotoCrop.between(points.first(),points.last()) else null
                                    val path = Path().apply {
                                        moveTo(points.first().x * this@Canvas.size.width, points.first().y * this@Canvas.size.height)
                                        points.drop(1).forEach { lineTo(it.x * this@Canvas.size.width, it.y * this@Canvas.size.height) }
                                    }
                                    val width = brush * min(this.size.width, this.size.height)
                                    if(shapeRect != null) {
                                        val position=Offset(shapeRect.left*this.size.width,shapeRect.top*this.size.height)
                                        val extent=Size((shapeRect.right-shapeRect.left)*this.size.width,(shapeRect.bottom-shapeRect.top)*this.size.height)
                                        if(shape == PhotoShape.ELLIPSE) drawOval(Color(ink),position,extent,style=Stroke(width)) else drawRect(Color(ink),position,extent,style=Stroke(width))
                                    } else drawPath(path, if(brushTool == PhotoBrush.ERASER || brushTool == PhotoBrush.BLUR) Color.White.copy(alpha=.5f) else Color(ink).copy(alpha=if(brushTool == PhotoBrush.MARKER) .4f else 1f), style = Stroke(width, cap = StrokeCap.Round))
                                    if (points.size == 1) drawCircle(Color(ink), width / 2, Offset(points.first().x * this.size.width, points.first().y * this.size.height))
                                }
                            }
                        }
                    }
                    if (source == null || rendering || busy) CircularProgressIndicator(Modifier.size(36.dp))
                }
                Column(Modifier.fillMaxWidth().heightIn(max=280.dp).verticalScroll(rememberScrollState()).padding(horizontal = 12.dp, vertical = 4.dp)) {
                    if (failure != null) {
                        Text(failure!!, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                        TextButton(onClick = { failure = null }) { Text("Закрыть сообщение") }
                    }
                    when (tool) {
                        Tool.CROP -> {
                            Text("Перетащите края или середину рамки", style = MaterialTheme.typography.bodySmall)
                            Row(Modifier.horizontalScroll(rememberScrollState())) {
                                TextButton(onClick = { crop = PhotoCrop.FULL }, enabled = !busy) { Text("Весь кадр") }
                                listOf("1:1" to 1f, "4:3" to 4f / 3f, "16:9" to 16f / 9f).forEach { (label, ratio) ->
                                    TextButton(onClick = { size?.let { crop = PhotoCrop.centered(it, ratio) } }, enabled = size != null && !busy) { Text(label) }
                                }
                                TextButton(onClick = { commit(PhotoEdit.Crop(crop)); crop = PhotoCrop.FULL }, enabled = !busy && !rendering && crop != PhotoCrop.FULL) { Text("Обрезать") }
                            }
                        }
                        Tool.ROTATE -> Column {
                            Row {
                                TextButton(onClick = { angle=0f; commit(PhotoEdit.Rotate(false)) }, enabled = !busy && !rendering) { Text("↶ 90°") }
                                TextButton(onClick = { angle=0f; commit(PhotoEdit.Rotate()) }, enabled = !busy && !rendering) { Text("↷ 90°") }
                                TextButton(onClick = { commit(PhotoEdit.Flip) }, enabled = !busy && !rendering) { Text("Отразить") }
                            }
                            Text("Горизонт: ${angle.toInt()}°",style=MaterialTheme.typography.bodySmall)
                            Slider(angle,{angle=it},valueRange=-45f..45f,enabled=!busy)
                            TextButton(onClick={commit(PhotoEdit.Straighten(angle));angle=0f},enabled=angle!=0f&&!busy&&!rendering){Text("Применить")}
                        }
                        Tool.DRAW, Tool.TEXT -> {
                            if (tool == Tool.TEXT) {
                                PhotoChoices(history.resolved.filterIsInstance<PhotoEdit.Text>(),selectedText,{it.text.take(16)},{selectText(it)},!busy)
                                OutlinedTextField(text, { text = it.take(200) }, Modifier.fillMaxWidth(), label = { Text("Текст — затем коснитесь фото") }, maxLines = 2, enabled = !busy)
                                PhotoChoices(PhotoTextStyle.entries,textStyle,{it.title},{textStyle=it},!busy)
                                PhotoChoices(PhotoFont.entries,textFont,{it.title},{textFont=it},!busy)
                                PhotoChoices(PhotoAlignment.entries,textAlignment,{it.title},{textAlignment=it},!busy)
                                Row {
                                    TextButton(onClick={stagedText?.let{commit(PhotoEdit.ReplaceText(it))};selectedText=null;text=""}){Text("Новый текст")}
                                    if(selectedText!=null) TextButton(onClick={commit(PhotoEdit.RemoveText(selectedText!!.id));selectedText=null;text=""}){Text("Удалить")}
                                }
                                Text("Выберите надпись и перетащите её по фото",style=MaterialTheme.typography.bodySmall)
                            } else {
                                PhotoChoices(PhotoBrush.entries,if(shape==null) brushTool else null,{it.title},{brushTool=it;shape=null},!busy)
                                PhotoChoices(PhotoShape.entries,shape,{it.title},{shape=it},!busy)
                                if(shape!=null) Row(verticalAlignment=Alignment.CenterVertically){Checkbox(filled,{filled=it});Text("Заливка")}
                            }
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                inkColors.forEach { color ->
                                    TextButton(onClick = { ink = color }, contentPadding = PaddingValues(2.dp), modifier = Modifier.size(36.dp), enabled = !busy) {
                                        Box(Modifier.size(if (ink == color) 28.dp else 20.dp).clip(CircleShape).background(Color(color)))
                                    }
                                }
                                Slider(if (tool == Tool.DRAW) brush else textSize, { if (tool == Tool.DRAW) brush = it else textSize = it },
                                    Modifier.weight(1f), valueRange = if (tool == Tool.DRAW) .004f.. .04f else .035f.. .15f, enabled = !busy)
                            }
                            OutlinedTextField(hexColor,{ value ->
                                hexColor=value.filter { it.isDigit() || it.uppercaseChar() in 'A'..'F' }.take(6)
                                if(hexColor.length==6) hexColor.toLongOrNull(16)?.let { ink=(it or 0xff000000).toInt() }
                            },label={Text("Свой цвет · HEX")},singleLine=true,modifier=Modifier.fillMaxWidth(),enabled=!busy)
                        }
                        Tool.FILTER -> {
                            PhotoChoices(listOf(0,1,2),filterMode,{listOf("Пресеты","Настройки","Кривые")[it]},{filterMode=it},!busy)
                            if(filterMode == 0) {
                            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                PhotoFilter.entries.forEach { preset ->
                                    FilterChip(selected = filterPreview && filter == preset, onClick = { filter = preset; filterPreview = true }, label = { Text(preset.title) }, enabled = !busy)
                                }
                            }
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Slider(amount, { amount = it; filterPreview = true }, Modifier.weight(1f), enabled = !busy)
                                TextButton(onClick = { commit(PhotoEdit.Filter(filter, amount)); filterPreview = false }, enabled = filterPreview && !busy && !rendering) { Text("Применить") }
                            }
                            } else if(filterMode == 1) {
                                PhotoChoices(PhotoTune.entries,tune,{it.title},{tune=it},!busy)
                                Text("${tune.title}: ${(tune.value(adjustments)*100).toInt()}",style=MaterialTheme.typography.bodySmall)
                                Slider(tune.value(adjustments),{adjustments=tune.set(adjustments,it)},valueRange=if(tune.positive) 0f..1f else -1f..1f,enabled=!busy)
                            } else {
                                PhotoChoices(listOf(0,1,2,3),curveChannel,{listOf("Все","Красный","Зелёный","Синий")[it]},{curveChannel=it},!busy)
                                PhotoCurve(adjustments.curves[curveChannel],{ values -> adjustments=adjustments.copy(curves=adjustments.curves.mapIndexed { i,old -> if(i==curveChannel) values else old }) },!busy)
                            }
                            if(filterMode!=0) Row {
                                TextButton(onClick={commit(PhotoEdit.Adjust(adjustments));adjustments=PhotoAdjustments()},enabled=!adjustments.isDefault&&!busy&&!rendering){Text("Применить")}
                                TextButton(onClick={adjustments=PhotoAdjustments()},enabled=!busy){Text("Сбросить настройки")}
                            }
                        }
                    }
                }
                    Row(Modifier.fillMaxWidth().padding(horizontal=12.dp).horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Tool.entries.forEach { item -> FilterChip(selected = tool == item, onClick = {
                            if(item!=tool) { pending.forEach { history=history.add(it) }; if(tool==Tool.CROP&&crop!=PhotoCrop.FULL) history=history.add(PhotoEdit.Crop(crop)); resetPending(); tool=item; points=emptyList() }
                        }, label = { Text(item.title) }, enabled = !busy) }
                    }
            }
        }
    }
}

@Composable
private fun <T> PhotoChoices(items: List<T>, selected: T?, label: (T)->String, onSelect: (T)->Unit, enabled: Boolean) {
    Row(Modifier.horizontalScroll(rememberScrollState()),horizontalArrangement=Arrangement.spacedBy(6.dp)) {
        items.forEach { item -> FilterChip(selected=item==selected,onClick={onSelect(item)},label={Text(label(item))},enabled=enabled) }
    }
}

@Composable
private fun PhotoCurve(values: List<Float>, onChange: (List<Float>)->Unit, enabled: Boolean) {
    val current by rememberUpdatedState(values)
    Canvas(Modifier.fillMaxWidth().height(100.dp).background(Color.Black).pointerInput(enabled) {
        if(enabled) detectDragGestures { change,_ ->
            change.consume(); val index=kotlin.math.round(change.position.x/size.width*4).toInt().coerceIn(0,4)
            onChange(current.mapIndexed { i,v -> if(i==index) (1-change.position.y/size.height).coerceIn(0f,1f) else v })
        }
    }) {
        for(i in 1..3) { drawLine(Color.DarkGray,Offset(size.width*i/4,0f),Offset(size.width*i/4,size.height));drawLine(Color.DarkGray,Offset(0f,size.height*i/4),Offset(size.width,size.height*i/4)) }
        val path=Path();values.forEachIndexed { i,v -> val p=Offset(size.width*i/4,size.height*(1-v));if(i==0)path.moveTo(p.x,p.y)else path.lineTo(p.x,p.y);drawCircle(Color.White,5.dp.toPx(),p) };drawPath(path,Color.White,style=Stroke(2.dp.toPx()))
    }
}
