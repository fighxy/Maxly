# Плавность уровня Telegram (iOS)

Цель: стабильность, перформанс скролла и анимации чата на уровне нативных мессенджеров. Стек остаётся своим; копируется поведение, не код.

## Слои

| Слой | Суть | Статус |
|---|---|---|
| **A. Движок ленты** | `UICollectionView` + recycling + invert (`scaleY(-1)`, новое в index 0) | Дефолт `TranscriptFeedEngine.collection` |
| **B. Рендер** | TextKit-высота текста, decode-ahead, сэмплер геометрии | Включено |
| **C. История** | Prefetch за ~20 строк до верха | Включено |
| **D. Motion** | `maxlyComposerFlight` | Включено |
| **Prefetch по скроллу** | `TranscriptImagePrefetch` — окно + направление | Включено |
| **Комментарии** | `CommentsCollectionFeed` на том же движке | Включено |

## A — UICollectionView (invert)

`TranscriptCollectionFeed` / `CommentsCollectionFeed`:

- Data source: новее сообщения первыми; `transform = scaleY(-1)` на коллекции и ячейках → визуально новое у низа.
- Вставка нового не сдвигает offset старых ячеек.
- Chrome: older-loader в секции у визуального верха, jump-newer — у низа.
- Высоты: `BubbleHeightCache` + off-main prewarm; TextKit через `BubbleTextMeasurer`.

Откат ленты чата: `UserDefaults` `maxly.transcript.feed` = `lazyStack`.

## B — Высота текста

`BubbleTextMeasurer.installAsHeightProvider()` в `AppContainer` → `BubbleHeightCache.textHeightProvider` (`NSString.boundingRect`, кегль `.body`).

## Prefetch картинок

`TranscriptImagePrefetch.plan(visibleRange:scrollingTowardOlder:)` + `ImagePipeline.prefetchDecoded`. Чат вызывает при скролле и смене `transcriptVersion`; комментарии — при скролле.

## Комментарии

`CommentsView` → `CommentsCollectionFeed` (пост + «Начало обсуждения» в older-секции, те же invert/prefetch/высоты).

## Дальше (если понадобится)

1. Self-sizing item sizes по id из кэша в compositional layout (сейчас estimated от последнего пузыря).
2. Prefetch decode строго по `indexPathsForVisibleItems` + velocity.
3. Убрать LazyVStack-путь, когда collection стабилен на всех сценариях.
