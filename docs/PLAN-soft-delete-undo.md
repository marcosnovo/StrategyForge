# Plan — #41 Soft-delete / Undo for chats (implement next iteration)

## Today (irreversible)
`AppModel.deleteConfiguration(id)` immediately: removes the `Configuration`, clears
dangling `continuedFrom` links, inserts a CloudKit tombstone, **deletes the transcript +
activity sidecars**, reselects, saves. A mis-click loses the whole conversation.

## Goal (backlog #41)
Retain sidecars ~30 days **or** a 10s "Undo" in the banner, plus a confirmation that
communicates the real cost. Ships in two layers; **Layer A is the next-iteration scope.**

## Layer A — 10s Undo (self-contained, high value)
Reuses the now-extracted `BannerCenter` for the action affordance.

1. **Capture instead of delete.** On delete, build an in-memory record:
   `RecentlyDeleted { config: Configuration /* incl. loaded transcript */,
   activityData: Data? /* read from the activity sidecar */, deletedAt }`. Do NOT delete
   the sidecars or insert the tombstone yet.
2. **Defer the hard delete.** Schedule the real removal (sidecar delete + tombstone +
   save) as a cancellable `Task` after ~10 s, keyed by id in
   `@ObservationIgnored private var pendingHardDelete: [Configuration.ID: (RecentlyDeleted, Task<Void,Never>)]`.
   A second delete or app quit flushes pending ones immediately.
3. **Undo affordance.** `BannerCenter.Banner` is `Equatable` and used in the auto-dismiss
   `banner == banner` check, so a closure can't live inside the enum. Add a SEPARATE
   observable on `BannerCenter`:
   `struct UndoAction { let label: String; let perform: () -> Void }` +
   `var pendingUndo: UndoAction?` (closure `@ObservationIgnored`, presence observed) and
   `func showWithUndo(_ message:String, undoLabel:String, undo:@escaping ()->Void)` that
   shows a success banner AND sets `pendingUndo`, clearing both after 10 s.
4. **Render it.** `BannerCapsule` (Theme.swift): when `model.bannerCenter.pendingUndo`
   is set, show an "Undo" button before the ✕ that calls `perform()` then dismisses.
5. **`AppModel.undoDelete(_ record:)`**: reinsert the config, rewrite transcript +
   activity sidecars from the captured bytes, restore `continuedFrom` links, drop the
   tombstone, reselect, cancel the pending hard-delete, save.
6. **Confirmation copy.** Update `sidebar.deleteMsg` to state the cost + the safety net
   ("Deletes the conversation and its history — you'll have 10 seconds to undo.").

**Files:** `BannerCenter.swift`, `AppModel.swift` (deleteConfiguration, undoDelete,
pendingHardDelete, flushSaves flushes pending), `Theme.swift` (BannerCapsule),
`Localization.swift` (`banner.undo`, revised `sidebar.deleteMsg`).

**Tests** (use the `init(storeDirectory:)` seam from #12): delete keeps sidecars until the
window elapses; `undoDelete` restores config + transcript + activity; hard-delete after
the window removes them and tombstones the id.

## Layer B — 30-day retention (follow-up)
- Hard delete MOVES sidecars to `deleted/<id>.<epoch>.{transcript,activity}.json` under
  `storeDirectory` instead of removing them.
- Persist `deletedChats: [DeletedChatRecord]` (id, name, deletedAt) in `PersistedState`.
- On `load()`, purge `deleted/` entries older than 30 days.
- A "Recently Deleted" sidebar section to restore within 30 days.

## Decisions for the founder
- **Scope:** Layer A only next iteration, or A+B together?
- **CloudKit interaction:** if the 10s window already synced the tombstone to another
  Mac, Undo re-creates the config (LWW re-push). Acceptable, or gate Undo before the
  first post-delete sync?
