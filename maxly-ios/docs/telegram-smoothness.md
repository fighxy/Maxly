# Плавность уровня Telegram (iOS)

Цель: стабильность, перформанс скролла и анимации чата на уровне нативных мессенджеров. Стек остаётся своим; копируется поведение, не код.

## Слои

| Слой | Суть | Статус в этой ветке |
|---|---|---|
| **A. Движок ленты** | `UICollectionView` + recycling + кэш высот вместо `LazyVStack` | Движок `TranscriptCollectionFeed` готов; включение через `UserDefaults` `maxly.transcript.feed` = `collection` после QA на устройстве |
| **B. Ужесточение рендера** | Decode-ahead картинок, кэш высот, реже геометрия на главном | Включено |
| **C. Данные / сеть** | Prefetch истории за ~20 строк до верха (как Android `PAGE_TRIGGER`) | Включено |
| **D. UX motion** | «Полёт» своего пузыря из поля ввода (`maxlyComposerFlight`) | Включено |

## A — UICollectionView

`MaxlyApp/Screens/Chat/TranscriptCollectionFeed.swift` — `UICollectionView` + `UIHostingConfiguration` для `TranscriptBubble`.

- Diffable data source по id строки.
- Оценка высоты из `BubbleHeightCache` (Presentation), уточнение после layout.
- Видимые рамки и низ ленты — из UIKit (без per-row `onGeometryChange`).
- Клавиатура: `keyboardDismissMode = .interactive`.
- Команды прокрутки — через `scrollToItem`, тот же `TranscriptScrollController`.

Переключение: `UserDefaults` ключ `maxly.transcript.feed` → `collection` | `lazyStack` (сейчас по умолчанию `lazyStack`, пока collection не пройдёт QA).

Проверка на устройстве перед сменой дефолта: открытие на unread, preload сверху, jump к цитате, follow bottom при новом, Reduce Motion, длинный чат 5k+.

## B — Рендер

1. `ImagePipeline.prefetchDecoded` — байты + decode в `NSCache` под размер ячейки.
2. `BubbleHeightCache` — эвристика высоты до показа (меньше blank overscroll у LazyVStack / быстрее layout у collection).
3. `TranscriptGeometrySampler` — отметки прочтения и «вниз» не чаще кадра (~16 ms), а не на каждое `onGeometryChange`.

## C — История

`HistoryPrefetch.shouldLoadOlder(visiblePrefix:trigger:)` — `trigger = 20`. Лента зовёт `loadOlder`, когда видна шапка **или** любая из первых 20 строк.

## D — Motion

`AnyTransition.maxlyComposerFlight` — своё сообщение сильнее поднимается от composer (36 pt, scale 0.88). Исходящие вставки в ленте используют его; чужие — прежний `maxlyBubble`.

## Дальше

1. Off-main TextKit sizing вместо эвристик в `BubbleHeightCache`.
2. Перевёрнутая лента (новое в index 0) после стабилизации collection.
3. Prefetch decode по видимому окну + направлению скролла.
4. Тот же движок для комментариев (`CommentsView`).
