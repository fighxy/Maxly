# Плавность уровня Telegram (iOS)

Цель: стабильность, перформанс скролла и анимации чата на уровне нативных мессенджеров. Стек остаётся своим; копируется поведение, не код.

## Слои

| Слой | Суть | Статус |
|---|---|---|
| **A. Движок ленты** | `UICollectionView` + recycling, старое сверху, новое снизу | Дефолт `TranscriptFeedEngine.collection` |
| **B. Рендер** | TextKit-высота текста, decode-ahead, сэмплер геометрии | Включено |
| **C. История** | Prefetch за ~20 строк до верха | Включено |
| **D. Motion** | `maxlyComposerFlight` | Включено |
| **Prefetch по скроллу** | `TranscriptImagePrefetch` — окно + направление | Включено |
| **Комментарии** | `CommentsCollectionFeed` на том же движке | Включено |

## A — UICollectionView

`TranscriptCollectionFeed` / `CommentsCollectionFeed`:

- Порядок как в мессенджере: старые сообщения сверху, новые снизу. Без `scaleY(-1)`.
- Подгрузка истории сверху сохраняет текущее место. Если читатель у низа, лента остаётся у последнего сообщения.
- Chrome: загрузка старого — сверху, прыжок к новым — снизу.
- Высоты: у каждой строки своя, `CollectionFeedLayout` + `BubbleHeightCache` (TextKit через `BubbleTextMeasurer`).
- Обычный индикатор прокрутки. Пузырь по-прежнему `UIHostingConfiguration`.

Откат ленты чата: `UserDefaults` `maxly.transcript.feed` = `lazyStack`.

## B — Высота текста

`BubbleTextMeasurer.installAsHeightProvider()` в `AppContainer` → `BubbleHeightCache.textHeightProvider` (`NSString.boundingRect`, кегль `.body`).

## Prefetch картинок

`TranscriptImagePrefetch.plan(visibleRange:scrollingTowardOlder:)` + `ImagePipeline.prefetchDecoded`. Чат вызывает при скролле и смене `transcriptVersion`; комментарии — при скролле.

## Комментарии

`CommentsView` → `CommentsCollectionFeed` (пост сверху, обсуждение вниз, те же высоты и prefetch).

## Дальше (если понадобится)

1. Полностью нативная отрисовка пузыря вместо `UIHostingConfiguration` в ячейке.
2. Prefetch decode строго по `indexPathsForVisibleItems` + velocity.
3. Убрать LazyVStack-путь, когда collection стабилен на всех сценариях.
4. Проверка на устройстве: контекстное меню, выделение текста, VoiceOver по длинной истории.
