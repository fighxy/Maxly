# Обмены ws2 для тестов звонков

Сигналинг звонков (ws2) реализован в Orbitle дважды: на Swift
(`orbitle-ios/Sources/OrbitleData/Calls`) и на Kotlin (`orbitle-shared/.../data/calls`,
Android и Desktop). Эти файлы — общие сценарии для обеих реализаций, чтобы они не
разошлись: кадры сервера, действия приложения и то, что клиент должен отправить в ответ.
Форматы взяты из рабочей реализации iOS (`CallSession.swift`, `Ws2Signaling.swift`).

Kotlin прогоняет их в `Ws2FixtureTest` (`orbitle-shared/src/test`), Swift — в
`CallSessionFixtureTests` (`orbitle-ios/Tests/OrbitleDataTests`). Обе реализации гоняют все
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
| `{"receive": {…}}` | сервер присылает этот JSON-кадр как есть |
| `{"receiveText": "ping"}` | сервер присылает текстовый кадр |
| `{"peerEvent": {"candidate": {"sdp", "sdpMid", "sdpMLineIndex"}}}` | WebRTC нашёл свой кандидат |
| `{"peerEvent": {"state": "CONNECTED"}}` | состояние соединения WebRTC |
| `{"expect": {…}}` | проверка после предыдущих шагов |

Поля `expect` (все необязательные):

- `phase` — `Connecting`, `Ringing`, `Active`, `Reconnecting`, `Ended`;
- `ended` — причина конца: `HungUp`, `RemoteHungUp`, `Declined`, `Rejected`, `Missed`,
  `NoAnswer`, `Busy`, `ConnectionLost`, `Failed`;
- `sent` — команды клиента после прошлой проверки, строго по порядку. Кадр сравнивается по
  подмножеству: каждое поле из фикстуры должно совпасть, остальные (`sequence`, SDP целиком)
  не проверяются. `[]` — клиент ничего не отправил;
- `sentTexts` — не-JSON кадры клиента после прошлой проверки (`pong`);
- `peer` — `null`, если соединения WebRTC ещё нет; иначе `microphone`, `iceServers`
  (число), `remotes` (типы принятых удалённых SDP по порядку), `candidates` (принятые
  кандидаты собеседника по порядку, `sdpMid: null` — без mid);
- `mediaConnected`, `socketClosed` — `true` / `false`.

На каждую команду фейковый сервер сам отвечает
`{"type": "response", "sequence": N, "response": "<команда>"}`. Свой SDP фейкового WebRTC —
`v=0…`, его текст фикстуры не проверяют.

## Swift

Тест Swift (`CallSessionFixtureTests` рядом с `CallSessionTests`) читает те же файлы с
диска, путь — от `#filePath` теста вверх до корня репозитория: `../../../test-fixtures/calls/ws2`. Ресурсом пакета их сделать нельзя: SwiftPM
не берёт файлы вне каталога пакета.
