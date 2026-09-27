# Saved treadmill planning profile contract

Contract: `saved-treadmill-planning/v1`. Issue: [#140](https://github.com/syamaner/paceprompt-ios/issues/140), parent [#139](https://github.com/syamaner/paceprompt-ios/issues/139).

Status: ratified by #140 / PR #168. The #141 implementation adds the local profile repository and lifecycle (4i–4l); the #142 implementation adds the shared selector and equipment-independent authoring validity (4a–4e). The #143 implementation adds pure historical compatibility and shared preview/edit/save acknowledgement (4f–4h); the #144 implementation adds fresh current-connection read-only revalidation and fail-closed recovery (4m), preserving existing execution guards. Implementation and simulator evidence do not establish signed-device protection or physical Bluetooth acceptance.

## Authority and architecture gate

The visual authority is design PR [#138](https://github.com/syamaner/paceprompt-ios/pull/138), exact source `1748aaf8043c4e37c81350235e9c2de5c2d0dfda`, not its moving branch. Its [index](https://github.com/syamaner/paceprompt-ios/blob/1748aaf8043c4e37c81350235e9c2de5c2d0dfda/design/treadmill-planning-profiles/README.md), PDF and HTML define screens 4a–4m and the accompanying flow, component, privacy and accessibility notes. PDF SHA-256 is `c030eaeb726f8c870f5b8480601e3bf700304f861ded8fb03c769b0e35040d0f`; HTML SHA-256 is `e1f641287a4795fe8beb826a891e63fa50475d4941728d5b7891f2fbf74defea`. They remain separate, unmodified artifacts; this issue does not merge #138.

The [FR30z execution profile](fr30z-physical-console-execution-profile.md) and [execution state machine](safety-gated-workout-execution-state-machine.md) govern live execution. Screens from earlier product slices are not a reason to revert accepted behaviour. In particular, replace 4m's obsolete claim that speed/inclination are set only on the console with: **Physical Start and Stop and the safety key remain authoritative. PacePrompt applies only validated speed and inclination targets after its live execution checks pass.** Preserve the red mismatch card and absence of Begin when blocked. The secondary recovery must allow choosing another treadmill as #144 specifies; cancelling to setup never scans or connects automatically. Choosing another plan may remain an additional existing route, not a substitute for that required recovery.

| Responsibility | Owns | Depends on |
| --- | --- | --- |
| Pure profile domain | Versioned identifiers, snapshot validity, age classification, comparison, revisions | Domain values only |
| Pure plan policies | Equipment-neutral canonical validity; historical comparison; separate live validation | Canonical plan and explicit evidence values |
| Application orchestration | Discovery decisions, selection, review/confirmation, repository transactions, draft revalidation | Consumer-owned profile repository, identity derivation, clock, identifier/randomness capabilities |
| Infrastructure adapters | CoreBluetooth evidence collection, opaque key derivation, protected atomic file I/O | Apple APIs; translate into domain values |
| Presentation | 4a–4m states, wording, navigation and accessibility | Application outcomes; no parsing, filesystem access or Bluetooth commands |

Dependencies point inward. CoreBluetooth objects/UUID types, filesystem URLs, CryptoKit keys and SwiftUI types do not cross the domain boundary. Compose adapters in the app composition root. Inject clock, identifier/randomness, identity derivation and repositories; alternate repositories satisfy the same behavioural contract tests. A future storage adapter must not change domain policies. Equipment support and schema changes require explicit versioned policy changes, not an open plugin mechanism for safety invariants.

## Closed invariants

1. A saved profile is historical planning information. It grants no connection, execution readiness, control authority or command permission.
2. Canonical plans remain equipment-neutral: no profile ID, identity token, profile name, ranges, snapshot, selected-profile revision or compatibility verdict enters plan schema, saved-plan storage, History or plan export.
3. Profile identity/name/ranges never enter provider payloads, disclosure previews of transmitted fields, logs, crash metadata, analytics, diagnostic export or evaluation artifacts. User-entered free text is still sent after existing consent; the app does not claim to redact equipment details a user types deliberately.
4. No raw CoreBluetooth peer identifier or Bluetooth name is persisted by the new profile subsystem. Only its installation-local opaque token is retained for deduplication. User-chosen names are private local data, not proof of identity.
5. Unknown, unavailable, incomplete, invalid and unsupported capability evidence are distinct. None becomes a usable recorded snapshot by defaulting to zero or inferring support from a characteristic's presence.
6. A profile comparison never clamps, rounds, edits or substitutes a plan target. Historical compatibility and age are separate verdicts.
7. Every execution uses freshly read, complete current-connection evidence and all existing FR30z profile, connection epoch, subscription, permission, capability-bound, acknowledgement and observation guards. A saved snapshot is never a fallback.
8. No new opcode, Start/Stop/Pause route, automatic reconnection, control reacquisition, automatic continuation or background profile work is authorised.

## Explicit product decisions

These answers are policy choices made under the operator's autonomous #140 delegation, with rationale below. They are not inferred from the drawings. Changing them requires a reviewed contract revision before implementation diverges.

| Decision | Selected behaviour | Rationale |
| --- | --- | --- |
| Staleness | Warn at age **greater than or equal to 30 × 24 hours** since the last accepted complete observation | Bounded, testable reminder; equipment validity cannot be inferred from age |
| Incompatible profiles | Keep visible and selectable; label mismatch in amber when a complete draft exists | A plan is equipment-neutral and may be used on another machine; hiding records would disguise the comparison |
| Rename | Detail-only, explicit Save/Cancel; 4k Rename opens the same detail editing flow | One consistent mutation/validation path; no inline list editing |
| Screen 4h | Offer **Save plan anyway** for an otherwise valid canonical plan | Saving is not execution; the named action explicitly acknowledges the historical mismatch |

Stale records remain selectable, comparable and savable; do not expire or delete them automatically. Show the last-confirmed date and **Saved profile is over 30 days old. Live compatibility is checked before execution.** Date age does not turn a historical pass into live readiness. At exactly the boundary, warn; immediately below it, do not. If the injected current time precedes the stored observation (clock rollback), show **Confirmation date cannot be verified** and treat age as uncertain, not fresh. No age threshold applies to live capability: live validity follows current-connection evidence and the execution policy, not a historical 30-day rule.

Without a complete draft, the picker cannot compute plan compatibility and must not invent an incompatible badge. A profile can be selected while its treadmill is out of Bluetooth range or disconnected. Mint **Current treadmill** is derived only from the independently valid current connection, never from selection, age or token lookup. Incompatible rows remain operable and have explicit text/glyphs; there is always a neutral **No treadmill selected** choice.

**Save plan anyway** leads through the existing exact-plan Save confirmation with the historical mismatch and affected steps still visible. This named action is the acknowledgement; no reusable consent bit or extra checkbox is stored. Returning to edit or changing the plan/profile invalidates the prior comparison and acknowledgement. Invalid structure, non-finite/unrepresentable quantities, wrong schema, unknown units or missing targets still block saving; this action bypasses only a historical equipment mismatch. Saved targets remain exact. Live mismatch never offers an execution-anyway action.

## Versioned local data

Use a dedicated protected profile store, separate from plan/history stores. Its envelope has `formatVersion: 1`, `identityDerivationVersion: 1`, a random 32-byte installation secret, monotonically increasing `storeRevision`, `lastSelectedProfileID` (null or an existing record), and a list of records. The secret and records share the same atomic replacement envelope so identity material cannot get out of step with the collection. The secret is private pseudonymisation material, not a provider credential or a treadmill authentication key.

Each record has exactly:

| Field | Contract |
| --- | --- |
| `profileID` | Random application-owned UUID string, immutable; not the CoreBluetooth identifier |
| `machineKey` | Lowercase 64-hex opaque derivation result; immutable and unique within the collection |
| `name` | Trimmed user-facing name; 1–80 grapheme clusters, at most 512 UTF-8 bytes, no control/newline characters; duplicate display names allowed |
| `equipmentType` | Closed `treadmill` value; other equipment needs a later contract |
| `recordRevision` | Positive integer; incremented for each committed record mutation |
| `snapshot` | Accepted complete speed/inclination target ranges and provenance below |

A snapshot contains `snapshotVersion: 1`; speed `minimumHundredthsKph`, `maximumHundredthsKph`, `incrementHundredthsKph`; inclination `minimumTenthsPercent`, `maximumTenthsPercent`, `incrementTenthsPercent`; `observedAt` as a valid RFC3339 UTC timestamp; and `provenance: {kind: ftmsRead, interpretationVersion: 1}`. Units are integers in the decoded FTMS resolution, not floating approximations. Speed bounds are unsigned 16-bit, inclination bounds signed 16-bit, both increments strictly positive, and minimum ≤ maximum. Validate target-support feature evidence and decoded ranges before constructing a snapshot; a range alone is insufficient. No raw packets, characteristic inventory, feature bytes, RSSI, firmware identifier, connection epoch or device diagnostics persist here. Raw current evidence remains in the existing live flow.

Both speed and inclination target capability must be known supported with complete valid ranges/increments from one current connection epoch. Known unsupported is not unknown, but it cannot create a usable v1 profile. Zero-width ranges are valid only with a positive representable increment; the sole bound is the only compatible target. Zero increment, missing range, contradictory flags, invalid width, partial reads or epoch changes reject construction. Never manufacture a flat zero-inclination range from unsupported inclination.

The envelope is bounded to 100 records and 256 KiB encoded UTF-8. A full collection rejects new discovery with an actionable **Delete a saved profile to add another** state; it does not evict records. Decode validates the entire envelope, uniqueness, field set/types, versions, sizes and selected reference before exposing usable records. A later limit or format change requires explicit versioning and migration tests.

### Opaque identity derivation

The CoreBluetooth adapter receives the peer identifier only in memory. Derive:

`machineKey = lowercaseHex(HMAC-SHA256(installationSecret, UTF8("paceprompt.planning-profile.v1:" + lowercaseCanonicalPeerUUID)))`

Validate a canonical peer UUID before derivation. Generate the secret once per new profile-store lifetime with secure randomness; inject deterministic synthetic material in tests. Use the full digest. A plain hash, Bluetooth name, advertisement name, MAC-address guess or shared global salt is prohibited. Cryptographic derivation belongs to the infrastructure identity adapter, not the pure domain.

Equal peer ID plus the same installation secret means the same local record. A different installation secret yields unrelated keys. The token is for local uniqueness only: it does not authenticate equipment, identify a serial-numbered physical machine, prove ownership or replace the characterised FR30z match. CoreBluetooth identifier changes may produce another profile for the same physical machine; do not merge by name/ranges. A hash collision or duplicate decoded machine key is corruption, not permission to silently merge records. Reset/reinstall can lose the store and its identity namespace; no cross-device persistence or sync is promised.

If identity material is missing or malformed, block the store. Do not generate a replacement secret around existing records or fall back to raw IDs. Explicit confirmed reset deletes the entire profile envelope and staging/recovery data; a new namespace is generated only for a later genuinely new store.

## Discovery and lifecycle transitions

Discovery is caused only by the existing explicit setup/connection flow. It adds no scanning, reconnecting or background behaviour. Complete evidence is projected once after a stable same-epoch read; repeated identical events are idempotent within that read. Repository writes use revision-aware transactions so discovery cannot overwrite a concurrent rename, deletion or review decision.

| Input/action | Local result |
| --- | --- |
| Complete first observation; key absent | Atomically create one record with generated ID and default unique **Treadmill N** name; 4k reports saved only after persistence succeeds |
| Same key, same ranges/increments on a later complete read | Preserve name/ID; update accepted observation date and revision; do not create a duplicate |
| Same key, any bound/increment differs | Keep accepted snapshot and date; expose transient 4l Saved/Newly read comparison; do not overwrite silently |
| **Update profile** | Revalidate pending observation, key, epoch and base record revision; commit exact new snapshot, preserving name/ID |
| **Keep saved profile** or cancel | Preserve snapshot/date; discard pending candidate; future complete changed reads may offer review again |
| Pending read becomes disconnected/invalid/obsolete | Invalidate Update; preserve historical record; no reconnect or inferred acceptance |
| Missing/unsupported/invalid capability | Show its distinct current state; do not create, refresh or change a record |
| Save/rename/update failure | Preserve canonical file; report failure, never display a success-only in-memory record |
| Rename Save | Validate name, commit with expected revision; never alter capability/date/key; Cancel changes nothing |
| Confirmed deletion | Remove record and selected reference in one transaction; leave all plans/history and live execution unchanged |

Generated names choose the smallest positive N not currently used by another exact **Treadmill N** name. User names are not deduplication keys. Name edits do not refresh age. Revisions, rather than wall-clock ordering, resolve concurrent mutations; a conflict requires reload and a fresh deliberate action, not silent last-write-wins. An observation timestamp is sampled when complete evidence arrives, not when a delayed review is accepted. The observation date is labelled last confirmed, never last connected.

The pending changed snapshot is process-only. If the user keeps the saved version, future authoring compares with that historical version, and live preflight still uses actual current values. Deletion consumes/cancels pending discovery/review work for that record in the current read generation: late or repeated same-generation events cannot recreate it. A later explicit connection/read may discover it as a new profile with a new profile ID; no persistent identity tombstone or lifetime suppression list is retained. Profile deletion never disconnects equipment, interrupts a workout or changes its commands. An existing immutable execution attempt continues under its own guards; it has no dependency on this mutable collection.

## Selection and plan validity

Selection is shared application authoring state, not a field of a saved plan. Store `lastSelectedProfileID` within the protected envelope and restore it only after a successful validated read. First use or a deleted selection becomes **No treadmill selected**. Protected/unreadable/corrupt/unsupported storage instead shows a distinct profile-unavailable explanation while allowing deliberate no-profile authoring; never mislabel unavailable storage as an empty collection. The separate plan repository must itself be writable before saving a plan.

4k **Use for planning** selects the successfully persisted record; discovery does not silently replace an existing selection. Picker Done commits selection; cancellation preserves it. The same selection component and summary order apply to Plans, manual creation and AI import. Selection changes never alter draft values. Deleting a selected profile clears selection and recomputes open drafts as unchecked. Profile updates or selection changes invalidate historical verdicts; recompute against the current selected record revision before preview/save. In-flight generation does not freeze an obsolete local verdict: the returned exact plan is checked locally against the then-current authoring selection.

Separate two validation products:

- **Canonical authoring validity** checks the existing schema, activity, step structure/order, labels, positive duration, explicit units and finite exactly representable canonical decimal targets, with non-negative speed and signed inclination, independent of any equipment. Do not impose a guessed machine range on no-profile authoring; negative speed is invalid, while negative inclination remains a representable decline target subject to historical/live checks. Preserve existing conversion/mapping semantics and prohibit repair. It is sufficient for exact preview and deliberate plan save.
- **Historical compatibility** compares every step's exact speed and inclination against the selected snapshot, inclusively, with exact increment alignment using the existing target validator's minimum-origin grid: `(target - minimum) / increment` must be an integer. Report every affected path/value/range/increment. This yields compatible, incompatible or unchecked, plus independent stale/date-uncertain warning. It is not the execution validator's validated token.

A future implementation must introduce a distinct consumer-owned authoring-validation capability/token; it must not forge the current `WorkoutPlanValidator.ValidatedPlan` using permissive dummy capabilities. `structuralIssues` alone is insufficient because it does not validate every target quantity. Existing live `validate(_:against:)` and execution readiness tokens retain their fail-closed meaning. Saved-plan repository acceptance must distinguish authoring validity from execution validity while leaving the canonical plan schema and exports unchanged. Manual and AI-mapped plans pass through the same authoring and historical policies.

Profile increments guide manual steppers but never trap an existing draft inside saved ranges. Preserve direct exact editing, including out-of-profile values, for 4h. With no profile, use canonical unit-resolution controls, not invented machine limits. Do not change provider schema/prompt/parser/mapping or claim that a selected profile controls generated targets.

## Provider privacy boundary

The production request currently includes existing speed/inclination support-state vocabulary from explicit live capability. Selection must not populate that snapshot from a saved profile, or add profile-derived capability states. For fixed user text and fixed pre-existing live request context, request bytes and the consent preview's transmitted fields are identical with no profile, each selected profile, a renamed profile, changed ranges, deletion and an unavailable store. With no live evidence, retain the existing unknown vocabulary; never turn historical support into live support.

Local authoring eligibility must be decoupled from requiring a live connection by #142 without changing the pinned prompt/examples/schema, model/route, response interpretation or local conversion/mapping. No-profile import still requires the existing per-request consent and provider availability. The selector has no reference to provider transport. Profile names/ranges may appear in separate on-device planning UI, never in the exact outbound payload/disclosure snapshot. Existing provider capability-state rules remain otherwise unchanged.

## Protected storage, migration and recovery

Resolve a dedicated `PlanningProfiles` subdirectory inside Application Support with platform APIs. Store directory, canonical envelope, staging and any bounded recovery copy require complete file protection and backup exclusion. Verify both attributes before exposing persisted data or reporting a successful write, including after atomic replacement. Failure to apply/verify them fails closed. The adapter must not follow a symbolic-link substitute for its owned store/staging paths. Never use UserDefaults, iCloud, synchronised Keychain, logs or crash attachments for profile data, selection or the identity secret.

Encode/validate a complete bounded replacement, write a same-directory protected staging file, synchronise it, then atomically replace canonical data and verify attributes. On pre-replacement failure, retain the last valid canonical state. On ambiguous post-replacement/attribute failure, report partial/unavailable state and re-read/verify before exposing records; do not assert that disk still holds the old revision. Do not promote orphan staging data automatically. Serialise all mutations, with expected revisions checked immediately before commit. A failed profile deletion keeps selection/record truthful to the re-read canonical state.

Missing canonical data with no staging is genuinely empty; missing canonical data with retained staging is interrupted-write/recovery state. Locked/protected data, I/O failure, corrupted JSON/fields, oversized data, duplicate identities and unknown format/derivation/snapshot versions are explicit blocked states. No partial record salvage, replacement-empty write, implicit reset or lossy best-effort migration. v1 has no predecessor. Future migrations require a version-specific deterministic transformer, full validation and atomic replacement while preserving IDs/keys/selection/accepted semantics; unsupported versions remain intact for recovery. Temporary files and any recovery copy remain protected/excluded and are deleted after validated completion or explicit confirmed reset; nothing is exported for diagnosis.

Delete profile removes only that record. A future separately confirmed **Reset saved treadmill profiles** removes the envelope, secret, selection, staging and recovery data; no automatic erasure is authorised by a read failure. Existing Reset local workout data retains its accepted scope unless a later explicit UI contract adds profiles to the confirmation. No recovery flow clears plan/history/credential data as a side effect. Complete Data Protection and backup exclusion need signed-device observation; fake/simulator attribute tests do not prove those platform properties.

## Presentation and accessibility

Map 4a–4e to one reusable full-width 44 pt minimum profile row and grouped sheet picker. The row reads as one accessibility element: name/none, speed range, inclination range, last-confirmed date, warning if any and Button. Summary order is **Speed a–b km/h · Inclination c–d %**, then **Last confirmed D Month YYYY**; list rows may use the specified abbreviation.

4f is neutral **Validated against saved profile**, profile/date and **Live compatibility will be checked before execution**. 4g is neutral **Treadmill compatibility not yet checked**, preserves primary Save and offers optional profile selection. A stale compatible snapshot keeps the historical verdict with a separate amber age warning; it never becomes mint. 4h is amber and identifies each affected step, exact target, recorded bounds and increment; Edit focuses that step, Save plan anyway follows the decision above. 4i–4l preserve the management/detail/read/change-comparison hierarchy. Saved/Newly read columns mark changes using words/glyphs and weight. A saved row remains neutral even when a separate current-connection badge is mint.

4m uses red only for live execution mismatch, names current range/affected targets, announces failure on appearance, and removes Begin. Unknown/unavailable live capability blocks execution with explicit evidence wording; never present it as a measured mismatch or permit continuation. Offer edit-plan or choose-another-treadmill recovery without modifying targets or silently connecting.

Every status has a word and distinct glyph; picker selection has a checkmark/selected trait, not tint alone. VoiceOver announces verdict before evidence, mismatch as an alert, affected step and its out-of-range value, and dates/units unambiguously. Dynamic Type stacks rows, wraps ranges, allows long names to wrap with badges below them and uses no fixed-height text container. Retain reduced-motion behaviour and focus after sheet dismissal/edit recovery. Delete confirmation names the profile and states that plans are unaffected and selection returns to none. All unsupported/unavailable states are non-colour distinguishable.

## Required downstream behavioural contract tests

These are acceptance specifications for later implementation, not tests executed by this documentation issue. Use synthetic identities, names, dates, ranges and failure adapters only.

| ID | Slice | Required cases and assertions |
| --- | --- | --- |
| P01 | #141 | Same canonical peer + secret deduplicates across reads; different secret/peer does not; names/ranges never establish identity; malformed identity/key fails |
| P02 | #141 | Partial reads, unknown/unsupported flags, malformed bounds, zero increment, mixed epochs fail construction; valid exact bounds and zero-width ranges retain exact units |
| P03 | #141 | First complete discovery, same-value refresh, changed bound/increment, Keep/Update/cancel/disconnect, stale base revision, rename races and repeated events; no silent overwrite/duplicate |
| P04 | #141 | Successful rename preserves snapshot/date/key; invalid/duplicate-display names, Cancel, deletion of selected/unselected record, full collection and reset failures preserve truthful state |
| P05 | #141 | Same repository suite for memory/file adapters: create/read/update/delete/select, expected-revision conflict, bounded decoding, duplicate IDs/keys, invalid selection, corruption/unsupported versions |
| P06 | #141 | Fault injection at encode/write/protection/backup/sync/replace/post-replace verification; old canonical preserved before replace, ambiguity reported after replace; locked data never becomes empty |
| P07 | #141 | Missing file vs orphan staging, unsupported migration, interrupted replacement, explicit reset, identity-secret loss, cleanup; no auto salvage/reset or unprotected file |
| P08 | #142 | Shared selector/Done/Cancel, no-profile authoring/import/save, restored/deleted/unavailable selection, direct edit without clamping, draft retention and revalidation on revision change |
| P09 | #142 | Exact outbound request + transmitted consent preview equality under all profile/selection/name/range/store states for fixed text/live context; fixed production resources/route/parser/mapping hashes unchanged |
| P10 | #143 | Manual and AI plans share canonical checks: non-finite/unrepresentable/missing/wrong-unit targets fail; no dummy capabilities or execution-valid token is manufactured |
| P11 | #143 | Speed-only/inclination-only/combined mismatch, every affected step, inclusive boundaries, exact minimum-origin increment alignment, no-profile, stale and clock-rollback; no target repair |
| P12 | #143 | 30-day boundary just below/equal/above; changed profile/draft clears prior verdict/Save-anyway acknowledgement; corrupt/unavailable store never produces historical success |
| P13 | #144 | Fresh live compatible pass, speed/inclination/combined mismatch, unknown/unsupported/incomplete/stale/epoch-change evidence, disconnected equipment and changed capability fail closed |
| P14 | #144 | Saved profile compatible but current machine incompatible remains blocked; different selected profile cannot override live evidence; every existing FR30z capability-bound/permission/acknowledgement/observation guard retained |
| P15 | #141–#144 | 4a–4m navigation/copy/colour/glyphs, VoiceOver order/announcements, Dynamic Type, reduced motion, 44 pt targets, long names and non-colour statuses |

Negative privacy assertions must inspect saved-plan/history/export bytes, outbound requests and diagnostic/crash logging adapters for profile-derived fields, tokens/names/ranges/secret. Use distinctive synthetic profile values and compare outputs while holding permitted live evidence and user text fixed; coincidentally equal live values are not evidence of a profile leak. Existing deliberate live diagnostics retain their separately accepted scope. Test profile repository persistence separately: it intentionally contains those private local fields. Signed-device checks for protection/backup and later physical live-preflight acceptance require separate operator authority. Documentation, synthetic tests and SDK references cannot establish physical machine uniqueness, runtime Data Protection or FTMS behaviour.

## Delivery and evidence boundary

#140 delivers only this contract and linked specification amendments, reviewed at the exact committed head. It does not add app/domain Swift, persistence code, fixtures containing real identity, UI, provider/prompt changes, FTMS procedures, release tags or physical-device observations. #141–#144 each remain separately authorised implementation slices. Their tests must prove the stated contracts; prose is not implementation evidence.

Primary API grounding, checked 26 September 2026: Apple [CBPeer.identifier](https://developer.apple.com/documentation/corebluetooth/cbpeer/identifier) describes a peer UUID, not a manufacturer serial identity; [CryptoKit HMAC](https://developer.apple.com/documentation/cryptokit/hmac) supplies keyed digest computation; [complete file protection](https://developer.apple.com/documentation/foundation/urlfileprotection/complete) and [backup exclusion](https://developer.apple.com/documentation/foundation/urlresourcekey/isexcludedfrombackupkey) supply platform attributes. The age, visibility, rename, save and limits above are PacePrompt policy choices, not Apple guarantees.
