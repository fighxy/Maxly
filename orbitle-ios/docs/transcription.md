# Расшифровка голосовых

Постановка Ивана от 02.10.2026: кнопка «→T» у голосового; пока идёт расшифровка и когда текст раскрыт, кнопка становится «^» и подсвечивается. Протокол и вид сверены с Komet (`voice_bubble.dart`, `messages.dart`) и правками Ивана в KometTeam/Komet#147.

## Протокол

- **Запрос** `AUDIO_TRANSCRIPTION` 202 `{chatId, messageId, mediaId}`, `mediaId` — `audioId` вложения. Ответ `{transcriptionStatus, transcription?}`: `1` — готово (пустой текст — речь не нашлась), `0` — сервер ещё работает.
- **Пуш** `TRANSCRIPTION_RESULT` 293 `{messageId, chatId?, mediaId?, transcriptionStatus, transcription}`, бывает вложен в `message`; без статуса — готово.

Ядро: `MessagesApi.transcribe`, `Transcription.from` (ответ и пуш), `MaxClient.transcribe`; мост — `transcribeVoice` и событие `transcription` (текст в `text`, статус в `unread`).

## Приложение

1. **Кнопка** справа от дорожки голосового (`VoiceMessageView`): капсула 40×28 с бледной заливкой цвета акцента (у своих — белого). Свёрнуто — «→Т», идёт расшифровка — круг, текст раскрыт — «^»; значок сменяется растворением с масштабом (0,18 с). Повторное нажатие сворачивает. Кнопки нет у неотправленного голосового.
2. **Текст** выезжает под дорожкой (0,2 с) во всю ширину пузыря обычным размером; время сообщения переезжает в конец его последней строки. Пустой — «Речь не распознана». Текст можно выделить.
3. **Где хранится**: в самом сообщении (`VoiceContent.transcript`, база). Повторное раскрытие сервер не спрашивает, сверка историей текст не стирает (история его не несёт).
4. **«Ещё расшифровываю»**: круг крутится до пуша (`SyncEngine` → `MessageRepositoryImpl.applyTranscription`), потом текст раскрывается сам. В Komet в это время раскрывается «транскрибация...»; здесь вместо надписи — круг на кнопке.
5. **Ошибка** (или пуша нет 60 с) — как в Komet, прямо в пузыре: раскрыто «Не удалось расшифровать», кнопка «^». Нажатие сворачивает, следующее «→Т» спрашивает сервер заново.

| Слой | Что |
|---|---|
| Domain | `MessageRepository.transcribe(messageId:attachmentId:)` |
| Data | `MaxCore.transcribeVoice`, `MaxAPI.transcribe`, `CoreTranscription`, `CoreEvent.Kind.transcription`; в репозитории — запрос, запись текста, пуш, сохранение при слиянии |
| Presentation | `TranscriptPhase`; `ChatViewModel.canTranscribe`, `transcriptPhase(for:)`, `toggleTranscript` |
| UI / App | кнопка и текст в `VoiceMessageView`, параметры `MessageBubble`, `TranscriptBubble.Snapshot` |

Тесты: `TranscriptionTest` (ядро), `TranscriptionDataTests`, `TranscriptToggleTests`.

Не сделано: расшифровка кружков (протокол тот же, `mediaId` — `videoId`) и настройка «Расшифровывать голосовые» в конфиденциальности (`AUDIO_TRANSCRIPTION_ENABLED`).
