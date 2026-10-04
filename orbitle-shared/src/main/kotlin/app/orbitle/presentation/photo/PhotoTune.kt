package app.orbitle.presentation.photo

enum class PhotoTune(val title: String, val positive: Boolean = false) {
    EXPOSURE("Экспозиция"), BRIGHTNESS("Яркость"), CONTRAST("Контраст"), SATURATION("Насыщенность"), WARMTH("Теплота"),
    SHADOWS("Тени"), HIGHLIGHTS("Света"), FADE("Выцветание",true), VIGNETTE("Виньетка",true), GRAIN("Зерно",true), SHARPEN("Резкость",true), BLUR("Размытие",true);
    fun value(a: PhotoAdjustments): Float = when(this) {
        EXPOSURE -> a.exposure; BRIGHTNESS -> a.brightness; CONTRAST -> a.contrast; SATURATION -> a.saturation; WARMTH -> a.warmth
        SHADOWS -> a.shadows; HIGHLIGHTS -> a.highlights; FADE -> a.fade; VIGNETTE -> a.vignette; GRAIN -> a.grain; SHARPEN -> a.sharpen; BLUR -> a.blur
    }
    fun set(a: PhotoAdjustments, value: Float): PhotoAdjustments = when(this) {
        EXPOSURE -> a.copy(exposure=value); BRIGHTNESS -> a.copy(brightness=value); CONTRAST -> a.copy(contrast=value); SATURATION -> a.copy(saturation=value); WARMTH -> a.copy(warmth=value)
        SHADOWS -> a.copy(shadows=value); HIGHLIGHTS -> a.copy(highlights=value); FADE -> a.copy(fade=value); VIGNETTE -> a.copy(vignette=value); GRAIN -> a.copy(grain=value); SHARPEN -> a.copy(sharpen=value); BLUR -> a.copy(blur=value)
    }
}
