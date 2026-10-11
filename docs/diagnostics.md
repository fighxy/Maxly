# Local diagnostic events (schema 1)

Available on iOS, Android and Desktop in the existing log export. Nothing is uploaded automatically.

## Reproduce a problem

1. In the log section, optionally enable detailed diagnostics for 15 minutes (automatically expires).
2. Open the affected chat, wait a few seconds, reproduce scrolling/history/sending.
3. In the log section tap **Проблема сейчас**. Save the log using the existing export action.
4. Find `problem.mark` and the same `marker` in `problem.snapshot`. Snapshots are the last observed states, not live screenshots; `observed_uptime_ms` identifies their age.

## Wire format

Structured entries are standalone JSON lines within the existing rotated `.log` files. Legacy human-readable entries remain for compatibility. Parse lines starting with `{` and `schema: 1`.

- `schema`: integer version; `time`: UTC ISO-8601; `uptime_ms`: elapsed monotonic time since diagnostic initialization.
- `session`: random identifier per process; `seq`: monotonically increasing event sequence, gaps indicate possible dropped events.
- `event`: stable event name; `fields`: map of strings (including decimal measurements and `true`/`false`).
- `operation`: pairs start/finish events; `screen`: transcript instance; `chat`/`message`/`media`: SHA-256 pseudonym salted by the process session, never a raw ID.
- Coordinates are native points on iOS, pixels on Compose. Compare normalized viewport fractions across platforms, not absolute values. Offsets follow the native list direction; `reverse` is explicit in Compose.

Field values are bounded to 256 characters, field count to 40, snapshots to 16 categories. Reserved content/credential field names are redacted. Call sites must only supply measurements, enums and pseudonymized identifiers: key filtering is defense in depth, not arbitrary payload sanitization. No new event records message bodies, captions, paths, signed URLs, SDP, ICE addresses, audio or video. Existing legacy log/crash text retains its existing policy.

## Coverage

| Area | Events |
| --- | --- |
| Startup | `app.start`, build SHA/core revision; `app.lifecycle` on iOS |
| Connection | `network.state`, `network.operation.start/finish`; iOS rate-limit and error kind |
| History | `history.open/older/newer/around.start/finish` (Kotlin), API operation timing (iOS), `history.request/page`, cache and boundary decisions (Kotlin) |
| Chat | `chat.open/close`, scroll request/applied (Compose); `chat.viewport` contains lifecycle/target reasons (iOS), visible frames, padding/insets, loading and restoration |
| Send | `send.deliver.start/finish` (Kotlin), API operation timing (iOS), `send.stage` and media upload progress milestones |
| Media | `media.cache`, `media.download.start/finish`, stored byte count |
| Calls | `call.state`: phase, mute, speaker, media connection, topology; existing detailed call log remains |
| Performance | sampled Compose main-dispatcher delays and JVM heap; iOS active-scene main-actor heartbeat delay/thermal state; Desktop existing UI watchdog |
| Notifications | explicit capability snapshot; Android incoming-call permission, posting result and action; iOS CallKit posting results, actions and audio activation. Message push is not implemented in this version; diagnostic events do not add push delivery. |

Viewport sampling is once/second, or four times/second during the temporary detailed mode. These measurements are observations, not proof of a particular UI cause. Dispatcher/heartbeat delays can reflect scheduling and lifecycle transitions.

## Writer and retention

File I/O is serialized off the caller thread. At most 512 pending entries; overload drops new entries and records `queue_dropped` on the next write. No recursive logging on disk errors. Rotation retains existing platform limits (Kotlin defaults 3 × 512 KiB, platform overrides preserved; iOS 5 × 1 MB). Reads/exports wait for accepted writes; abrupt process termination may lose queued entries. iOS respects the existing logging switch. Detailed mode never enables disabled logging.

## Validation

Kotlin tests cover concurrent JSON ordering, redaction, snapshots/marker, cancellation terminal events, rotation and clear/read barriers. Swift tests cover matching JSON/privacy/marker semantics and existing file-store rotation/export behavior. Device reproduction remains necessary to diagnose the original blank-space bug; this change deliberately adds observation without altering scrolling rules.
