# Saved treadmill planning profiles

These reviewer-supplied artifacts are the visual design authority for the
saved-treadmill-profile backlog created on 20 September 2026:

- [PDF design board](./PacePrompt%20Screens.pdf)
- [HTML design board](./PacePrompt%20Screens.html)

Both files are retained byte-for-byte as supplied. Their SHA-256 digests are:

| Artifact | SHA-256 |
| --- | --- |
| `PacePrompt Screens.pdf` | `c030eaeb726f8c870f5b8480601e3bf700304f861ded8fb03c769b0e35040d0f` |
| `PacePrompt Screens.html` | `e1f641287a4795fe8beb826a891e63fa50475d4941728d5b7891f2fbf74defea` |

## Required screen family

The implementation issues refer to the screen identifiers printed in the
artifacts:

- **4a-4e:** plan entry points and the shared treadmill-profile selector for
  AI and manual authoring;
- **4f-4h:** preview states for saved-profile validation, no-profile planning,
  and authoring-time incompatibility;
- **4i-4l:** saved-profile list, profile details, newly discovered profiles,
  and capability-change review;
- **4m:** fail-closed live preflight when the connected treadmill does not
  match a saved plan's requirements.

The accompanying flow, component, state, content, privacy, and accessibility
annotations are part of the visual contract. Implementations must match the
existing PacePrompt visual language shown in the artifacts. Mint denotes a
current connection; historical saved-profile states remain neutral, planning
mismatches use amber, and red is reserved for a live preflight mismatch.

## Product and safety boundaries

The artifacts define desired presentation and flow; they do not independently
authorise implementation or override repository safety policy. In particular:

- workout creation and import must work without a live treadmill connection;
- choosing no treadmill must still permit creating and saving a plan;
- a saved profile is historical planning information, never evidence of a
  current connection or authority to issue a command;
- current live capabilities must be checked again before execution;
- no profile identity, name, capability range, or other treadmill information
  may be sent to the workout-import provider;
- saved plans remain equipment-neutral rather than embedding a treadmill
  profile identifier;
- this design set does not authorise new FTMS opcodes, automatic reconnection,
  background execution, provider changes, analytics, cloud storage, or release
  work.

The existing FR30z physical-console execution profile remains authoritative
until an approved issue amends a conflicting contract. In particular, adding a
durable local profile identity requires an explicit privacy and persistence
contract before implementation.

## Decisions still requiring ratification

The design board intentionally leaves these product decisions open:

1. when a saved profile becomes stale enough to warrant a warning;
2. whether the picker shows profiles whose recorded ranges cannot satisfy the
   current plan;
3. whether renaming is available inline or only from profile details;
4. whether screen 4h keeps **Save plan anyway** or blocks saving until the
   mismatch has been acknowledged or corrected.

Implementation issues must preserve these as explicit decisions and must not
infer answers from the mock-ups.
