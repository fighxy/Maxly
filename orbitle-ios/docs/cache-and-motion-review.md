# Cache and motion fixes — 2026-10-01

The review covered main at `5de1fb2333b278225e734a5a902aad1c662dd248` after reports of bubbles flying up when opening chats/channels, abrupt tab bar appearance, and poor long-text composer geometry.

## Changes

- Image bodies read decoded memory only. File/URLCache reads and image decoding run in background tasks. Concurrent sizes share source bytes, decoded entries remain keyed by URL and pixel size, and view task identity includes both. Cache clearing cancels old work and prevents it from repopulating memory. Local recording previews keep working through the asynchronous file path. Attachment previews also decode outside body.
- Every chat opening explicitly restores history. Cache and server catch-up use reload semantics; the stream is restarted with an authoritative baseline after synchronization. Late snapshots from the old subscription cannot override the new generation. Live insertion animations resume afterward.
- The transcript tracks a scroll target and bottom-marker geometry with hysteresis. Deletions/reorders/history no longer masquerade as new messages. The unseen count includes all newly appended incoming messages. Comments also avoid pulling a reader out of history on new incoming messages.
- Reaction geometry uses the quick curve near the bottom, instead of bouncing the whole transcript. History readers receive no transcript insertion animation.
- One stable chat List adapts its selection for edit mode. Folder switches force reload even when almost all IDs overlap. A large window trim cannot bypass the change limit by reporting one appended item.
- The root tab container owns tab-bar visibility. Chat and list no longer independently switch its toolbar preference.
- The composer and comments use fixed-radius rounded glass for multiple lines. Record/send controls occupy the same 44 pt slot. Recording and remaining list/filter curves honor Reduce Motion.

## Validation

Regression tests cover concurrent image sizes, cache clearing during an in-flight request, async local-file decoding, cache/server restoration on repeated opening, live insertion afterward, small overlapping folders, and large window shifts.

This Linux workspace has no Swift/Xcode runtime. Local validation is source review and `git diff --check`; Swift tests and app compilation must run in the existing macOS GitHub Actions workflow. These are not frame-rate measurements or device UI tests. Check long-text cursor/selection, keyboard dismissal, tab-bar push/pop (including canceling an interactive pop), and prepend/reactions while reading history on an iPhone before merging.

## Remaining protocol limitation

An own-message echo can arrive before the send acknowledgement supplies its server ID. Orbitle retains local identity and removes the duplicate once the acknowledgement arrives, but it cannot reliably associate an earlier server ID with a local send. The core currently does not expose the correlation required for a definitive fix. This PR does not merge records based on matching text or hide potentially real messages from another device. A separate core/client correlation change is required to remove that intermediate duplicate safely.

The fixed shape and button slots address composer layout; replacing the native TextField or changing its five-line limit requires an observed cursor/scroll problem on device, rather than assuming that native multiline editing is broken.
