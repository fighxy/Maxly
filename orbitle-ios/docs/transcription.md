# Расшифровка голосовых

Постановка Ивана от 02.10.2026: кнопка «→T» у голосового; пока идёт расшифровка и когда текст раскрыт, кнопка становится «^» и подсвечивается. Протокол сверен с Komet (`voice_bubble.dart`, `messages.dart`).

## Протокол

- **Запрос** `AUDIO_TRANSCRIPTION` 202 `{chatId, messageId, mediaId}`, `mediaId` — `audioId` вложения. Ответ `{transcriptionStatus, transcription?}`: `1` — готово (пустой текст — речь не нашлась), `0` — сервер ещё работает.
- **Пуш** `TRANSCRIPTION_RESULT` 293 `{messageId, chatId?, mediaId?, transcriptionStatus, transcription}`, бывает вложен в `message`; без статуса — готово.

Ядро: `MessagesApi.transcribe`, `Transcription.from` (ответ и пуш), `MaxClient.transcribe`; мост — `transcribeVoice` и событие `transcription` (текст в `text`, статус в `unread`).

## Приложение

1. **Кнопка** справа от дорожки голосового (`VoiceMessageView`): «→T» на бледной плашке; во время расшифровки — круг загрузки; текст раскрыт — «^» на плашке цвета акцента (у своих — белой). Повторное нажатие сворачивает. Кнопки нет у неотправленного голосового.
2. **Текст** выезжает под дорожкой; пустой — «Речь не распознана». Текст можно выделить.
3. **Где хранится**: в самом сообщении (`VoiceContent.transcript`, база). Повторное раскрытие сервер не спрашивает, сверка историей текст не стирает (история его не несёт).
4. **«Ещё расшифровываю»**: круг крутится до пуша (`SyncEngine` → `MessageRepositoryImpl.applyTranscription`), потом текст раскрывается сам. Пуша нет 60 с — уведомление «Расшифровка ещё не готова, попробуйте позже».
5. **Ошибка** — в строке ошибки над полем ввода, кнопка снова «→T».

| Слой | Что |
|---|---|
| Domain | `MessageRepository.transcribe(messageId:attachmentId:)` |
| Data | `MaxCore.transcribeVoice`, `MaxAPI.transcribe`, `CoreTranscription`, `CoreEvent.Kind.transcription`; в репозитории — запрос, запись текста, пуш, сохранение при слиянии |
| Presentation | `TranscriptPhase`; `ChatViewModel.canTranscribe`, `transcriptPhase(for:)`, `toggleTranscript` |
| UI / App | кнопка и текст в `VoiceMessageView`, параметры `MessageBubble`, `TranscriptBubble.Snapshot` |

Тесты: `TranscriptionTest` (ядро), `TranscriptionDataTests`, `TranscriptToggleTests`.

Не сделано: расшифровка кружков (протокол тот же, `mediaId` — `videoId`) и настройка «Расшифровывать голосовые» в конфиденциальности (`AUDIO_TRANSCRIPTION_ENABLED`).
