# Обмены ws2 для тестов звонков

Сигналинг звонков (ws2) реализован в Orbitle дважды: на Swift
(`maxly-ios/Sources/MaxlyData/Calls`) и на Kotlin (`maxly-shared/.../data/calls`,
Android и Desktop). Эти файлы — общие сценарии для обеих реализаций, чтобы они не
разошлись: кадры сервера, действия приложения и то, что клиент должен отправить в ответ.
Форматы взяты из рабочей реализации iOS (`CallSession.swift`, `Ws2Signaling.swift`).

Kotlin прогоняет их в `Ws2FixtureTest` (`maxly-shared/src/test`), Swift — в
`CallSessionFixtureTests` (`maxly-ios/Tests/MaxlyDataTests`). Обе реализации гоняют все
файлы каталога, так что новый сценарий сразу проверяется на обеих. Правка фикстур
перезапускает и Android/Desktop-тесты, и iOS-тесты в CI.

## Файл

```json
{
  "name": "outgoing-direct",
  "description": "…",
  "role": "CALLER | CALLEE | JOINER",
  "isGroup": false,
  "selfId": 10,
  "conversationId": "conv",
  "signalingUrl": "wss://sig.test/ws?userId=10&token=t",
  "steps": [ … ]
}
```

Шаги выполняются по порядку:

| Шаг | Что делает |
|---|---|
| `{"do": "start"}` | `CallSession.start()` — открыть ws2 |
| `{"do": "accept", "video": false}` | ответить на входящий |
| `{"do": "hangUp"}` | положить трубку |
| `{"do": "setCamera", "on": true}` | `CallSession.setCamera(on)` — включить или выключить камеру |
| `{"do": "setScreenSharing", "on": true}` | `CallSession.setScreenSharing(on)` — показ экрана |
| `{"receive": {…}}` | сервер присылает этот JSON-кадр как есть |
| `{"receiveText": "ping"}` | сервер присылает текстовый кадр |
| `{"peerEvent": {"candidate": {"sdp", "sdpMid", "sdpMLineIndex"}}}` | WebRTC нашёл свой кандидат |
| `{"peerEvent": {"state": "CONNECTED"}}` | состояние соединения WebRTC |
| `{"peerAnswer": "v=0…"}` | фейковый WebRTC отвечает на следующие оферы этим SDP (`answerSdp` текущего соединения; шаг ждёт, пока соединение появится) |
| `{"expect": {…}}` | проверка после предыдущих шагов |

Поля `expect` (все необязательные):

- `phase` — `Connecting`, `Ringing`, `Active`, `Reconnecting`, `Ended`;
- `ended` — причина конца: `HungUp`, `RemoteHungUp`, `Declined`, `Rejected`, `Missed`,
  `NoAnswer`, `Busy`, `ConnectionLost`, `Failed`;
- `sent` — команды клиента после прошлой проверки, строго по порядку. Кадр сравнивается по
  подмножеству: каждое поле из фикстуры должно совпасть, остальные (`sequence`, SDP целиком)
  не проверяются. `[]` — клиент ничего не отправил;
- `sentTexts` — не-JSON кадры клиента после прошлой проверки (`pong`);
- `sdpLabels` — подписи своего видео в SDP последней команды клиента, которая несёт SDP
  (`description` у `accept-producer`, `data.sdp.sdp` у `transmit-data`): все вхождения
  `u<цифры>:s<ЗАГЛАВНЫЕ>` (регулярное выражение `u[0-9]+:s[A-Z]+`) по порядку, без повторов,
  например `["u10:sSCREEN"]`. Сравнивается весь список;
- `peer` — `null`, если соединения WebRTC ещё нет; иначе `microphone`, `iceServers`
  (число), `remotes` (типы принятых удалённых SDP по порядку), `candidates` (принятые
  кандидаты собеседника по порядку, `sdpMid: null` — без mid), `sendVideo` (видео, с которыми
  звали `CallPeer.sendVideo`, по порядку: `"camera"`, `"screen"`; `[]` — новых отправителей
  не было), `slot` (что сейчас в слоте SFU: `"camera"`, `"screen"` или `null` — пусто);
- `mediaConnected`, `socketClosed` — `true` / `false`.

На каждую команду фейковый сервер сам отвечает
`{"type": "response", "sequence": N, "response": "<команда>"}`. Свой SDP фейкового WebRTC —
`v=0…` (или тот, что задал `peerAnswer`); его текст фикстуры не проверяют, кроме подписей
`sdpLabels`.

Слот SFU в фейковом WebRTC: `fillVideoSlot(mids, video)` с непустыми `mids` кладёт `video` в
слот (и возвращает `true`), `stopVideo(video)` освобождает слот, если в нём это видео.
Дорожки фейкового медиа: камера `cam-track`, экран `screen-track`.

## Показ экрана через SFU (`screen-share-sfu`)

Слот своего видео у сервера один, и экран в нём главнее камеры. Включить или выключить экран
или камеру — значит поменять дорожку в отправителе слота (`fillVideoSlot` с `mid` слота из
последнего офера; новый отправитель через `sendVideo` не добавляется). Сервер узнаёт видео по
подписи в SDP, а замена дорожки SDP не меняет, поэтому после замены клиент шлёт тот же
локальный ответ ещё раз `accept-producer` (те же `ssrcs` и `sessionId`) с подписью слота по
`mid`: `u<id>:sSCREEN` или `u<id>:sCAMERA`, — и потом `change-media-settings`. Пока идёт показ
экрана, `isVideoEnabled` — `false` (камера только своё превью). Пустой слот подписи не
требует; слот, не согласованный на отправку, заполнится со следующим офером сервера.

## Swift

Тест Swift (`CallSessionFixtureTests` рядом с `CallSessionTests`) читает те же файлы с
диска, путь — от `#filePath` теста вверх до корня репозитория: `../../../test-fixtures/calls/ws2`. Ресурсом пакета их сделать нельзя: SwiftPM
не берёт файлы вне каталога пакета.
