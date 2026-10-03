# Product copy inventory and validation — #209

Scope: [#209](https://github.com/syamaner/paceprompt-ios/issues/209), using the
[#208 audit](https://github.com/syamaner/paceprompt-ios/issues/208) and main
`530a435902b2ab30f62784b6c64aa98ad12259af` as the source baseline. All examples
and tests are synthetic. User health screenshots and values are not retained here.

## Architecture gate

Existing presenters translate domain state into labels and accessibility text;
views own layout and actions. Lifecycle status strings remain at their existing
presentation seam. No new copy framework or domain dependency is introduced.
History now derives its outcome icon and Health success colour from typed state,
not English labels. Preflight has an explicit presentation-only `isReading` flag
set only by an actual read. Import reasons/paths stay structured in the outcome;
ordinary feedback maps them to product labels. Export field lists remain unchanged
in the schema; presentation supplies readable descriptions.

Closed invariants: no changed reducer guards, control commands, clock, save policy,
identity, wire/schema, persistence, provider request, permission purpose or tap
sequence. Phone Health saving stays suppressed for Watch or invalid ownership.
A valid Watch source is displayed only for schema 3 plus the Watch ownership
envelope. Incomplete interchange means unconfirmed details, not necessarily
missing steps. Known pre-finish failure and uncertain finish/receipt failure have
different Watch recovery confirmation text. No retry or replacement save is added.

## Screen/state/route matrix

| Surface and real route | States and producers | Copy boundary and synthetic checks |
| --- | --- | --- |
| Home tab → Set up treadmill | `HomePresentation`: idle, scanning, connecting, reading, connected, malformed, unsupported, unavailable, disconnected, failed | Connection is not readiness; exact range values remain. Home unit/UI scenarios cover distinctions. Raw parser details stay in setup diagnostics (#210). |
| Plans → select plan → Prepare workout → Check workout | `WorkoutSessionHost`, `WorkoutPreflightPresentation`, `LivePreflightFailure`, production binding read result → preflight views | Reading says checking; missing/expired/changed reads are blocked. Every exact speed/incline validation issue keeps its field/step association. Unit tests exercise both same `readComplete=false` cases. |
| Begin workout → physical Start waiting | Preflight status/VoiceOver values and hints | No settings sent versus control granted remain distinct; matching acknowledgement tests retain reducer assertions. |
| Exercise portrait and landscape | `WorkoutExercisePresentation` → exercise view, all stages and axis evidence | Plan / Your setting / Treadmill keep prescribed, changed and observed values separate. Requested, sent, Bluetooth delivery, treadmill acceptance and reported match retain distinct cases. Countdown/actions unchanged. |
| Phone Watch preparation, binding, ending, timeout and recovery | `PhoneWatchLifecycle` → session host status | Asked to finish is not a confirmed Health save. Phone save suppression remains. |
| Watch initial, recording, paused, saved, incomplete, discarded, uncertain, stop and next-workout dialogs | `WatchWorkoutLifecycle` → `WatchWorkoutModel.Presentation` → scroll view/dialog | Known not-saved versus unconfirmed save; saved-cleanup failures still begin with Workout saved. Zero usable steps still discard. Watch lifecycle regressions exercise failure stages and complete prefix lacking final confirmation. |
| Plans list/create/edit/review/save/delete | `PlansPresentation`, `PlansViewModel`, `ManualPlanIssuePresentation` → Plans view | Locked, unreadable, interrupted, newer-format and incomplete-save states preserve data and disable mutations. Typed validation maps internal vocabulary while preserving useful numeric limits. Existing mutation-failure tests retain repository-state assertions. |
| Profile picker/manage/review/rename/delete/mismatch confirmation | `PlanningProfileLifecycle`, `PlanningProfile`, selector/profile views | Saved limits are for planning; live treadmill is checked again. Same buttons, mismatch acknowledgement and routes. |
| History list/detail → Apple Health save confirmation | `HistoryHealthExportPresentation` → History view | History vs Health outcomes remain separate. Semantic symbols/colour; invalid ownership says source unavailable. Phone uncertain-save versioned retry remains distinct from Watch no-replacement policy. |
| History detail → View plan | Existing read-only plan sheet | Previously labelled Repeat; now truthfully labelled View plan. No new repeat workflow. Delete remains disabled. |
| Plans → Import workout → Review what will be sent | Import view/model + typed failures | Recipient OpenRouter/OpenAI, model, exact entered text, sent data, cost, retention and per-request consent remain. Known codes/paths stay in outcome and diagnostics, never interpolated in routine feedback. No provider call used for validation. |
| Settings → OpenRouter key | Credential state → display labels | Missing, present, replacing, deleting, failed remain distinct. Failed replacement keeps old key; failed deletion does not confirm removal. |
| Plans/History → export selection → review → Share | Export presenter descriptions and failure messages | Exact schema output unchanged; names/dates/identifiers/settings/provenance/units disclosed in plain language. Recipient chosen in OS share sheet; copies may remain with recipient. Local temporary cleanup errors remain explicit. |
| Settings privacy/about and accessibility text | Settings view + all affected view hints/values | Remove development-slice/FTMS labels. Preserve sensor-read/write disclosure, phone suppression and retained sensor samples after discarded workout. Permission purpose strings unchanged. |

## Copy decisions

The table below records exact source fragments before and after this slice, grouped
by producer. Interpolations are source placeholders, never personal values.
Clear existing messages remain unchanged; this is a bounded ordinary-flow inventory,
not a claim that diagnostics or every internal source string has been renamed.

### `PacePrompt/Presentation/WorkoutExercisePresentation.swift`

| Before | Product copy |
| --- | --- |
| "Submitted" | "Sent" |
| "ATT accepted" | "Bluetooth delivered" |
| "FTMS acknowledged" | "Setting accepted" |
| "Stale treadmill report" | "Waiting for an update" |
| Last reported; telemetry is stale | Last reported; no recent update |
| No trustworthy treadmill distance is available | The treadmill has not provided a usable distance |
| Current-segment \(overriddenAxes.joined(separator: " and ")) override | Your \(overriddenAxes.joined(separator: " and ")) setting for this step |
| Restoring effective speed | Restoring your speed setting |
| PacePrompt is waiting for fresh treadmill-reported movement. No target is confirmed. | Waiting for the treadmill to report movement. Your speed and incline settings are not yet confirmed. |
| Intent, submission, ATT, FTMS acknowledgement and treadmill observation remain separate. | Sending your speed and incline settings, then checking what the treadmill reports. |
| Fresh treadmill evidence confirms the current effective targets. | The treadmill reports your current speed and incline settings. |
| The effective target differs from the plan for this segment only. | Your changed setting applies to this step only. |
| Telemetry is delayed or stale, so timing is frozen. This does not mean the treadmill stopped; confirm below only after the operator observes it stationary. | Treadmill updates are delayed, so the timer is paused. The belt may still be moving. Confirm it has stopped only after you have seen it stop. |
| The current segment and effective targets are preserved while active time is frozen. | Your step and settings are kept while the timer is paused. |
| Speed is restored before inclination. The step timer counts fresh reported movement during the ramp. | Restoring speed, then incline. The step timer continues while the treadmill reports movement. |
| PacePrompt sends no Stop command. End workout appears after stationary evidence. | Stop the belt at the console. You can finish here once it has stopped. |
| Stationary confirmed | Treadmill stopped |
| End workout saves the local app attempt and sends no FTMS Stop. | End workout saves to History on this iPhone. It does not stop the treadmill. |
| Saving the local app attempt. The treadmill remains under physical-console control. | Saving to History on this iPhone. Use the console to stop the treadmill. |
| The local app attempt is saved. No FTMS Stop was sent. | Saved to History on this iPhone. Apple Health saving has a separate status. |
| Physical state is uncertain. Use the console and safety key; no automatic resume is available. | The treadmill may still be moving. Use its console and safety key. This workout will not resume automatically. |
| A typed \(axis) intent exists; submission is not yet recorded. | Your \(axis) change is waiting to be sent. |
| The \(axis) procedure was submitted; ATT acceptance is not yet recorded. | Your \(axis) change was sent. Bluetooth delivery is not yet confirmed. |
| ATT accepted the \(axis) write; FTMS has not yet acknowledged it. | Bluetooth delivery confirmed. Waiting for treadmill acceptance. |
| FTMS acknowledged \(axis); later treadmill observation is still required. | The treadmill accepted the \(axis) setting. Waiting for it to report the new value. |
| Acknowledgements are complete; waiting for a later joint treadmill report. | The treadmill accepted both settings. Waiting for a new speed and incline report. |
| A later fresh treadmill report matches the effective \(axis) target. | The latest treadmill report matches your \(axis) setting. |
| The last treadmill report is older than the accepted freshness window. | The displayed value is from an earlier treadmill update. |
| Current \(axis) evidence is malformed, contradictory or procedurally failed. | The \(axis) change failed or the treadmill sent an unusable update. |
| No current evidence confirms the effective \(axis) target. | Your \(axis) setting is not yet confirmed by a current treadmill report. |

### `PacePrompt/Views/WorkoutExerciseView.swift`

| Before | Product copy |
| --- | --- |
| Evidence, not assumptions | Your settings and treadmill readings |
| Actual is treadmill reported. Planned is the segment target. Effective includes any current-segment override. | Treadmill shows the reported value. Plan shows the original setting. Your setting includes changes for this step. |
| valueRow(label: "Actual" | valueRow(label: "Treadmill" |
| valueRow(label: "Effective" | valueRow(label: "Your setting" |
| valueRow(label: "Planned" | valueRow(label: "Plan" |
| Reduced motion: static status | Animation off |
| Status changes use a gentle pulse only | Gentle status animation |
| Changes only the current segment effective target within the current live machine range and increment. | Changes this step only, using the settings supported by the connected treadmill. |
| Ends this workout using the current stopped-treadmill evidence. Stop the belt at its console. | Finishes the workout after the treadmill has stopped. Use the console to stop the belt. |
| Operator-confirmed stationary | Confirm the belt has stopped |
| Confirm only after directly observing that the treadmill is stationary. Silence, stale telemetry and disconnection are not stationary evidence. | Confirm only after you have seen the belt stop. A lost connection or missing update does not mean it has stopped. |
| I observed the treadmill stationary | I can see the belt has stopped |

### `PacePrompt/Presentation/WorkoutPreflightPresentation.swift`

| Before | Product copy |
| --- | --- |
| Connect the accepted FR30z before preflight can continue. No control request has been made. | Connect your Reebok FR30z to check this workout. No control request has been sent. |
| Reading current capabilities, subscriptions and profile evidence. Control is not held. | Checking the treadmill settings and live updates. PacePrompt does not yet have control. |
| Unsupported profile | Treadmill not supported |
| Treadmill data stale | Treadmill updates delayed |
| Readiness locked | Workout not ready |
| A Request Control procedure is in progress. Intent, submission or ATT acceptance alone is not control. | Asking the treadmill to allow speed and incline changes. Waiting for its confirmation. |
| Preflight failed | Workout preparation failed |
| This connection does not exactly match the accepted FR30z profile. Control remains unavailable. | This connection does not match the supported Reebok FR30z. PacePrompt cannot change its settings. |
| Current speed and inclination evidence is older than 2 seconds. Last-known values are not readiness. | Speed and incline updates are delayed. Waiting for current readings before you can begin. |
| A required current fact is unknown, invalid or unsafe. Begin workout remains unavailable. | Some treadmill checks are missing or did not pass. You cannot begin yet. |
| The current profile and workout are ready. Begin workout sends nothing and waits for physical Start. | The checks have passed. Tap Begin workout, then use Start on the treadmill console. |
| A matching FTMS Request Control success is held. Fresh movement is still required before any target. | The treadmill allows setting changes. Waiting for it to report movement before sending them. |
| No Control Point procedure has been sent. Fresh reported movement permits Request Control. | No settings have been sent. PacePrompt will ask for control once the treadmill reports movement. |
| Control state is not valid for physical Start. | PacePrompt cannot proceed with this workout yet. |
| Reading current treadmill capabilities. Execution remains blocked. | Checking supported treadmill settings. Please wait. |
| The capability read belongs to a different connection. | The connection changed during the check. Prepare the workout again. |

### `PacePrompt/Views/WorkoutPreflightView.swift`

| Before | Product copy |
| --- | --- |
| "Preflight" | "Workout check" |
| Live treadmill bounds | Treadmill limits |
| Speed ceiling | Maximum speed |
| Incline ceiling | Maximum incline |
| Current treadmill capability ceilings | Current treadmill limits |
| The operator starts and stops the belt using the physical treadmill console. The console and safety key remain authoritative throughout the workout. | Start and stop the belt at the treadmill console. Keep the console and safety key within reach. |
| Starts the app attempt and waits for physical Start. It sends no treadmill procedure. | Prepares the workout. Use Start on the treadmill console to begin moving. |
| Apple Watch owns this recording | Record with Apple Watch |
| Ready for a later deliberate save | Save from History after your workout |
| Planned only - neither target has been submitted, acknowledged, reached or observed. | These are planned settings. They have not been sent to the treadmill or confirmed. |
| Keep the console and safety key immediately reachable. PacePrompt is waiting for fresh treadmill-reported movement; waiting is not proof that the belt is moving. | Keep the console and safety key within reach. PacePrompt is waiting for the treadmill to report movement. |
| LIVE COMPATIBILITY CHECK | TREADMILL CHECK |
| Execution blocked | Workout cannot begin |
| INCOMPATIBLE TARGETS | SETTINGS TO REVIEW |
| Current treadmill requirement | Supported setting |
| Physical Start and Stop and the safety key remain authoritative. PacePrompt applies only validated speed and inclination targets after its live execution checks pass. | Use the treadmill console and safety key to start and stop. PacePrompt checks the treadmill before changing speed or incline. |

### `Shared/WatchInterchange/PhoneWatchLifecycle.swift`

| Before | Product copy |
| --- | --- |
| Watch ownership could not be reserved. Nothing was launched. | Could not prepare Apple Watch recording. Nothing was started. |
| Watch interchange timed out. Save result unavailable on iPhone. | Apple Watch did not respond in time. Check the recording and save status on your Watch. |
| Watch-owned; save result unavailable on iPhone | Check Apple Watch for the save result. iPhone saving is disabled for this workout. |
| Watch reconnected; previous connection gaps remain incomplete. | Watch reconnected. Some earlier workout details could not be confirmed. |
| Watch recording end sent. Check the save result on Apple Watch. | Asked Apple Watch to finish recording. Check your Watch for the save result. |
| Watch interchange is incomplete. | Some workout details could not be sent to Apple Watch. |

### `Shared/WatchInterchange/WatchWorkoutLifecycle.swift`

| Before | Product copy |
| --- | --- |
| Start a Watch-assisted workout on iPhone. | Start a workout with Apple Watch on your iPhone. |
| Save result uncertain. No replacement workout will be created. | Save not confirmed. Check Apple Health. This workout will not be saved again. |
| Protected workout state is unavailable. | Workout details could not be read. Unlock your Watch and reopen PacePrompt. |
| Ready. Previous outcome retained. Start a new workout on iPhone. | Ready for your next workout. Start it on iPhone. |
| Recovery could not be saved. Previous outcome retained; try again when Watch is unlocked. | Could not prepare your next workout. Unlock your Watch and try again. The previous result is kept. |
| Workout saved with incomplete intervals. | Workout saved. Some step details could not be confirmed. |
| Workout not saved: no execution intervals were received or usable. | Workout not saved: no usable step details arrived from iPhone. |

### `PacePromptWatch/PacePromptWatchApp.swift`

| Before | Product copy |
| --- | --- |
| Start a Watch-assisted workout on iPhone. | Start a workout with Apple Watch on your iPhone. |
| Active energy is calculated by HealthKit. | Calories are estimated by Apple Watch. |
| Keep previous outcome and continue | Prepare next workout |

### `PacePrompt/Views/WorkoutSessionHost.swift`

| Before | Product copy |
| --- | --- |
| Current capability or subscriptions do not match the accepted FR30z execution profile. No control authority is granted. | The treadmill settings or live updates do not meet the requirements for a Reebok FR30z workout. PacePrompt cannot change its settings. |
| A new deliberate preparation is required. Choose another treadmill to return to setup. | Prepare this workout again. Choose another treadmill to return to setup. |
| The exact plan fails current capability range or increment validation. | Some plan settings are not supported by the connected treadmill. |
| "Live capability bounds" | "Treadmill limits" |
| Continue to preflight | Check workout |
| Continue reads current treadmill ranges and increments. Every exact plan target and manual adjustment must fit that evidence. | Continue checks which speed and incline settings the connected treadmill supports. Your plan and any changes during the workout must fit those limits. |
| Preflight unavailable | Workout check unavailable |
| The current connection matches the accepted FR30z production profile. | This connection supports Reebok FR30z workouts. |
| Connect the accepted FR30z and wait for current capabilities and subscriptions. | Connect your Reebok FR30z and wait for its settings and live updates to be checked. |
| This validates and prepares the local workout. No treadmill procedure is sent until after Begin workout and fresh physical-Start movement. | This checks your workout. Settings are sent only after you tap Begin workout and the treadmill reports movement from using Start at its console. |

### `PacePrompt/Presentation/HomePresentation.swift`

| Before | Product copy |
| --- | --- |
| Radio powered on and authorised for this app. | Bluetooth is on and PacePrompt has permission to use it. |
| No scan started. Capability is unknown until you scan. | Choose Set up treadmill to find and check your treadmill. |
| Scan started by you. Capability remains unknown while scanning. | Looking for nearby treadmills. Their supported settings are not yet known. |
| capability not yet read. | supported settings not yet checked. |
| Reading capability | Checking treadmill |
| current capability evidence is being discovered. | checking supported settings. |
| Prior capability values are stale and are not shown as current. | Reconnect in treadmill setup to check its current settings. |
| "\(message) Wake the console and retry the user-started scan." | "Wake the treadmill console and try scanning again." |
| "\(message) Resolve Bluetooth status before trying setup again." | "Check Bluetooth permission and turn it on before trying setup again." |
| Capability malformed | Treadmill settings unreadable |
| A current capability value could not be decoded. Open setup to inspect it and retry. | The treadmill sent an unreadable setting. Open setup to check the connection. |
| Capability unsupported | Settings not supported |
| Current feature evidence reports speed or inclination target-setting as unsupported. | This treadmill reports that speed or incline cannot be changed by the app. |
| read range evidence: speed | supported speed |
| Capability unavailable | Treadmill check unavailable |
| A current capability read failed: \(lastError) | Could not read the supported treadmill settings. Open setup to check the connection. |
| A required read-only capability characteristic is unavailable. | The treadmill does not provide the settings needed for a workout. |
| is connected, but current decoded capability evidence is incomplete. | is connected. Its supported settings are still being checked. |

### `PacePrompt/Presentation/PlansPresentation.swift`

| Before | Product copy |
| --- | --- |
| Capability snapshot | Treadmill settings |
| Review validates canonical plan values independently of equipment. It does not save, contact or control the treadmill. | Review checks your plan before saving. Treadmill compatibility is checked before a workout begins. |
| Canonical plan values validated independently of equipment. Live compatibility is checked before execution. Review and confirmation do not contact or control the treadmill. Only confirmation writes to local storage. | Your plan has been checked. Confirm to save it on this iPhone. Treadmill compatibility is checked before a workout begins; saving does not control the treadmill. |
| Protected data is unavailable until this iPhone is unlocked. Your saved plans are untouched. | Unlock this iPhone and try again. Your saved plans are unchanged. |
| The plan store could not be opened. Nothing was written or deleted, and your saved data was preserved. | Your saved plans could not be opened. They have not been changed or deleted. |
| Saved plans are corrupt | Saved plans cannot be read |
| The stored records could not be decoded safely. They were preserved unchanged; editing and export are disabled. | Your saved plans could not be read. They are kept unchanged, but cannot be edited or exported. |
| Last save finished partially | Last save was interrupted |
| A partial write was detected. Existing plans were preserved; editing and export are disabled. | The last save did not finish. Existing plans are kept; editing and export are unavailable. |
| This plan store uses schema v\(version); this build reads v\(SavedPlanStoreSchema.currentVersion). The data is kept as-is and cannot be shown safely. | These plans use a format this version of PacePrompt cannot open. They are kept unchanged. |
| A saved plan uses schema v\(version); this build reads v\(WorkoutPlanSchema.currentVersion). The store is kept as-is and cannot be shown safely. | A plan uses a format this version of PacePrompt cannot open. Your saved plans are kept unchanged. |
| A stale staging file was detected. Readable plans remain visible and preserved, but all changes are disabled. | A previous save did not finish cleanly. You can view readable plans, but changes and export are unavailable. |
| PacePrompt could not check for a staging file. Saved data was preserved, and all changes are disabled. | PacePrompt could not check the last save. Your plans are kept, but changes and export are unavailable. |

### `PacePrompt/Presentation/PlansViewModel.swift`

| Before | Product copy |
| --- | --- |
| The plan could not be \(editing ? "updated" : "saved") during \(stage.displayName). Existing plans were left unchanged. Try again. | The plan could not be \(editing ? "updated" : "saved"). Existing plans are unchanged. Try again. |
| Deletion was not confirmed during \(stage.displayName). The existing plan remains listed. Try again. | The plan could not be deleted. It remains listed. Try again. |
| historical mismatch | difference from the saved treadmill settings |
| The selected plans could not be encoded. Saved plans were left unchanged and no file was shared. | The selected plans could not be prepared for sharing. Saved plans are unchanged and no file was shared. |
| Protected temporary storage could not be prepared. Saved plans were left unchanged and no file was shared. | A private copy could not be prepared. Saved plans are unchanged and no file was shared. |
| The export could not be written to protected temporary storage. Saved plans were left unchanged. | The private export copy could not be saved. Your saved plans are unchanged. |
| Complete file protection could not be verified, so the temporary export was not shared. | The export copy could not be protected, so it was not shared. |

### `PacePrompt/Profiles/PlanningProfile.swift`

| Before | Product copy |
| --- | --- |
| Saved treadmill profiles are unavailable while protected data is locked. | Unlock this iPhone to read your saved treadmill profiles. |
| Saved treadmill profiles use an unsupported version. Nothing has been migrated. | This version of PacePrompt cannot open your saved treadmill profiles. They are unchanged. |
| An interrupted profile write needs recovery. Nothing has been promoted. | A profile save was interrupted. Your saved profiles have not been replaced. |
| Use a trimmed name of 1–80 characters without control characters. | Use a name of 1–80 visible characters, without spaces at the beginning or end. |
| Complete current speed and inclination capability reads are required. | Connect your treadmill and wait for its speed and incline settings to be checked. |

### `PacePrompt/Profiles/PlanningProfilesView.swift`

| Before | Product copy |
| --- | --- |
| Saved ranges are historical planning evidence. Live compatibility is checked before execution. | Use saved treadmill limits to plan your workout. The connected treadmill is checked again before you begin. |
| Selection uses historical planning information. Live compatibility is checked before execution. | This uses previously saved treadmill settings. The connected treadmill is checked again before you begin. |
| Historical profile — this does not establish execution readiness. | Saved settings help you plan. They do not confirm that a treadmill is ready now. |
| The saved profile has not been changed. Current live capability still governs execution; updating changes historical planning evidence only. | Your saved profile is unchanged. Updating it changes the limits used for planning; the connected treadmill is still checked before each workout. |
| You can use this historical profile for planning while disconnected. Live compatibility is checked before execution. | You can plan with these saved settings while disconnected. The treadmill is checked again before you begin a workout. |
| Capability discovery | Treadmill check |

### `PacePrompt/Health/HistoryHealthExportPresentation.swift`

| Before | Product copy |
| --- | --- |
| Watch-owned; save result unavailable on iPhone | iPhone saving is disabled for this workout. Check Apple Watch for its recording and save status. |
| Recorded independently on Apple Watch | Recording status is unavailable on iPhone |
| Physically uncertain | Treadmill stop unconfirmed |
| Executed interval timing is unavailable (\(reason.rawValue)). No detail was inferred. | Recorded step timing is unavailable. Missing details have not been estimated. |
| Schema v1 stays local and is not reconstructed for Apple Health. | This older workout does not contain the details needed to save to Apple Health. It remains in History. |
| This persisted in-progress attempt is shown as interrupted; completion is unknown. | This workout was interrupted. PacePrompt cannot confirm whether it finished. |
| This outcome or execution timeline is not eligible for Apple Health. | This workout does not contain the details needed to save to Apple Health. |
| Not eligible for Apple Health | Cannot save to Apple Health |
| Unlock this iPhone, then retry. Stored workouts were preserved and were not treated as empty. | Unlock this iPhone, then retry. Your workouts are kept. |
| PacePrompt could not read the protected history file. The file was preserved. | PacePrompt could not read your saved workouts. They are kept unchanged. |
| The stored file could not be decoded safely. It was preserved without guessing or showing an empty library. | Your saved workouts could not be read. They are kept unchanged. |
| A partial history write was detected | A History save was interrupted |
| The incomplete data was preserved. PacePrompt will not promote, merge or guess its contents. | The last save did not finish. Your existing workout data is kept unchanged. |
| This store uses format v\(version). It was preserved unchanged and cannot be shown safely. | This version of PacePrompt cannot open your saved workouts. They are kept unchanged. |
| One workout uses schema v\(version). The complete store was preserved unchanged. | A workout uses a format this version of PacePrompt cannot open. History is kept unchanged. |
| One workout plan uses schema v\(version). The complete store was preserved unchanged. | A workout plan uses a format this version of PacePrompt cannot open. History is kept unchanged. |
| Readable workouts remain visible, but Apple Health save-state changes and JSON export are disabled while the stale staging file is preserved. | A previous save did not finish cleanly. You can view readable workouts, but saving to Apple Health and exporting are unavailable. |
| PacePrompt could not check for a staging file. Workouts remain visible, but Apple Health save-state changes and JSON export are disabled. | PacePrompt could not check the last save. You can view workouts, but saving to Apple Health and exporting are unavailable. |
| prescribed segments completed | planned steps completed |
| Prescribed · | Plan · |
| Effective · | Your settings · |
| Observed · | Treadmill readings · |
| Executed interval detail is unavailable in schema v1. PacePrompt does not reconstruct it from plan targets or summary timestamps. | This older workout has no recorded interval details. Missing details have not been estimated from the plan. |
| Executed interval detail is unavailable. No detail was inferred. | Recorded interval details are unavailable. Missing details have not been estimated. |
| The workout-history export failed without changing persistent History. | The export failed. Your saved workouts are unchanged. |
| The selected workouts could not be encoded. No export file was created. | The selected workouts could not be prepared for sharing. No export file was created. |
| Protected temporary storage could not be prepared. No export file was created. | A private copy could not be prepared. No export file was created. |
| The protected temporary export could not be written. | The private export copy could not be saved. |
| Complete file protection could not be verified, so the temporary export was not shared. | The export copy could not be protected, so it was not shared. |
| interval metadata record | recorded interval |
| Each interval contains prescribed, effective-target and separately observed speed and inclination. | Each interval includes the original plan settings, your changed settings and separate treadmill readings for speed and incline. |
| Local execution remains in History | Workout details remain in History |

### `PacePrompt/Views/HistoryView.swift`

| Before | Product copy |
| --- | --- |
| Button("Repeat") | Button("View plan") |
| Prescribed plan | Original plan |
| Executed intervals | Recorded intervals |
| Immutable plan snapshot | Original plan |
| Repeat \(plan.suggestedName) | Plan: \(plan.suggestedName) |
| Review only. This does not arm, connect to or operate a treadmill, and it does not create or save a new plan. | This is the original plan for this workout. Viewing it does not start a workout or save a new plan. |
| Included evidence | Included details |
| JSON export creates a deliberate protected copy. Deletion is not available in this version. | Export a JSON copy to share. Deleting workouts is not available in this version. |
| The export contains prescribed, effective-target and separately observed speed and inclination, timing, outcome and optional trustworthy distance. PacePrompt removes the protected temporary copy when sharing finishes or is cancelled. Persistent History is unchanged. | The export includes original plan settings, your changed settings, separate treadmill readings, timing, outcome and available distance. Choose who receives it in the share sheet. PacePrompt removes its temporary copy after sharing or cancellation; copies you share may remain with the recipient. Your History is unchanged. |

### `PacePrompt/History/WorkoutHistoryExport.swift`

| Before | Product copy |
| --- | --- |
| Version-1 workouts remain readable but cannot be reconstructed for JSON export. | This older workout can be viewed but lacks the details needed for JSON export. |
| Workout summary schema v\(version) is not supported for JSON export. | This workout uses a format this version of PacePrompt cannot export. |
| Plan schema v\(version) is not supported for JSON export. | This plan uses a format this version of PacePrompt cannot export. |
| This workout has no recorded execution timeline and cannot be exported without inference. | This workout has no recorded interval timing, so it cannot be exported. |
| This workout has no measured active duration and cannot be exported without inference. | This workout has no recorded active duration, so it cannot be exported. |
| This workout is not internally consistent enough for structured JSON export. | Some workout details do not agree, so it cannot be exported. |

### `PacePrompt/Views/SettingsView.swift`

| Before | Product copy |
| --- | --- |
| Current slice | Available features |
| FTMS control | Treadmill adjustments |
| Reviewed speed and incline only | Speed and incline during workouts |
| optional accepted treadmill distance | available treadmill distance |
| Workouts without usable intervals are discarded; sensor samples may already remain in HealthKit. | Workouts without usable step details are not saved; heart rate and calorie samples may still remain in Apple Health. |

### `PacePrompt/Import/WorkoutImportView.swift`

| Before | Product copy |
| --- | --- |
| Local validation | Plan details to review |
| Review remote-send disclosure | Review what will be sent |
| Remote-send disclosure | Review AI request |
| to produce an untrusted structured workout proposal. | to suggest a workout plan for you to review. |
| We send the exact text below, en-GB locale, the supported unit vocabulary, the fixed versioned instructions, schema and eleven examples, and only your current speed/inclination capability states. Capability ranges remain on this device. Saved treadmill profile names, identities and historical ranges are not sent. | We send the text below, British English language settings, supported units, instructions, the required plan format and eleven examples. We also send whether speed and incline changes are supported. Treadmill limits, saved profile names and identities stay on this device. |
| OpenRouter credential | OpenRouter key |
| Refresh credential status | Check key status |
| The credential operation failed. A failed replacement preserves the previous key; a failed deletion does not confirm removal. | The key could not be read or changed. A failed replacement keeps the previous key; a failed deletion does not confirm that it was removed. |

### `PacePrompt/Views/PlansView.swift`

| Before | Product copy |
| --- | --- |
| Only this separate confirmation action writes the validated plan to local storage. | Confirm to save this plan on your iPhone. |
| Invalid values are rejected. PacePrompt never clamps, repairs or replaces a target for you. | Correct the highlighted values to continue. PacePrompt will not change them for you. |

### `PacePrompt/Execution/ProductionWorkoutExecutionBinding.swift`

| Before | Product copy |
| --- | --- |
| No fresh preflight read | Treadmill settings have not been checked yet. |
| Current connection is unavailable or a read is already pending | The treadmill is disconnected or a settings check is already running. |
| Complete current capability reads could not be requested. In setup, wait for pending reads or explicitly disconnect and reconnect before continuing. | Could not start the treadmill check. In setup, wait for any check to finish, or disconnect and reconnect before continuing. |
| Current capability read expired. Choose another treadmill, then explicitly disconnect and reconnect before continuing. | The treadmill check expired. Choose another treadmill, then disconnect and reconnect before continuing. |
| Current capability read is malformed or incomplete | Some treadmill settings could not be read. |
| Capability evidence became stale while the app was inactive | The treadmill needs checking again after PacePrompt was in the background. |
| Capability evidence changed; a fresh preflight read is required | The treadmill settings changed. Check the workout again. |
| Current capability read failed | Could not check the supported treadmill settings. |
| Current capability read timed out or its clock cannot be verified. Choose another treadmill, then explicitly disconnect and reconnect before continuing. | The treadmill check did not finish in time. Choose another treadmill, then disconnect and reconnect before continuing. |
| Current connection was replaced or disconnected | The treadmill connection changed or was lost. |

### `PacePrompt/Profiles/PlanningProfileLifecycle.swift`

| Before | Product copy |
| --- | --- |
| Connect explicitly to read complete treadmill capabilities. | Connect your treadmill to check its supported settings. |
| Capability read incomplete — no saved profile change. | The treadmill check is incomplete. Your saved profile is unchanged. |
| Disconnected — saved profiles remain historical. | Disconnected. Saved profiles keep the previously checked settings. |
| Saved profile confirmed by complete read. | Saved profile matches the connected treadmill. |

### `PacePrompt/Profiles/PlanningProfileSelector.swift`

| Before | Product copy |
| --- | --- |
| Choose historical planning information. This does not establish execution readiness. | Choose saved treadmill settings for planning. The connected treadmill is checked again before a workout. |
| Create a plan without equipment validation. | Create a plan without checking treadmill limits yet. |
| Increments guide editing; enter any exact target directly. Saved ranges never clamp your draft. | Use the buttons to adjust by the shown amount, or type a value. Saved limits do not change your draft. |
| Checked against \(profile.name). Live capability has not been checked. | Checked against saved settings for \(profile.name). The connected treadmill has not been checked yet. |
| Connect a treadmill before execution to verify speed and inclination targets. | Connect a treadmill before your workout to check its speed and incline settings. |
| Confirm exact plan despite historical mismatch | Save despite different treadmill limits? |
| Review exact affected targets before acknowledging this historical mismatch | Review the settings that differ from your saved treadmill limits |
| Writes this exact canonical plan to local storage | Saves this plan on your iPhone |
| Saved profiles record historical planning information. Live compatibility is checked before execution. | Saved profiles help you plan. The connected treadmill is checked again before your workout. |
| Saved planning information. Live compatibility is checked before execution. | Saved treadmill settings for planning. The connected treadmill is checked before your workout. |
| You can create and save the plan now. Live compatibility is checked before execution. | You can save the plan now. The connected treadmill is checked before your workout. |
| Live compatibility will be checked before execution. | The connected treadmill will be checked before your workout. |

## Generated mappings and semantic changes

- Import path `steps.targetSpeed.value` → “step speed”; duration/unit, incline,
  activity, step type/repetitions and capability paths have explicit labels.
  Unknown paths use “workout details” without echoing provider input.
- Import `missingCredential` → add OpenRouter key; authentication → check key;
  credits → check balance; restricted route → account settings; transport →
  internet connection; timeout/unavailable/rate limit remain distinct. Identity
  failures explain that the agreed service could not be verified. Every failure
  keeps “Nothing was saved” and renewed consent before a new request.
- Validation `nonFiniteTarget` → enter a valid number; unknown/unsupported/invalid
  capability → distinct supported-setting messages. Structural/numeric range and
  increment messages retain exact corrective values. Domain diagnostics unchanged.
- Credential raw enum → No key saved / Key saved on this iPhone / Replacing your
  key / Deleting your key / Key status needs attention.
- Planned steps remain distinct from recorded intervals: an override or pause can split a step into multiple intervals.
- Export schema paths → readable grouped descriptions; field lists and encoded
  bytes are unchanged. Contract fixture assertions remain.
- History icon uses `outcomeSymbol(summary)`; Health colour uses `isSaved` only
  after eligibility, valid ownership and actual saved state. In-progress, physical
  uncertainty, invalid ownership and active save cannot imply confirmed Health save.
- Watch next-workout confirmation says not saved for known pre-finish failure and
  unconfirmed for uncertain finish/receipt, without changing retirement or controls.

## Validation and follow-up

Complete `scripts/validate_local.sh` passed on 3 October 2026 with Xcode 27.0
(27A266a), SDK 27.0 and the dedicated iPhone 17 Pro / iOS 26.5 simulator:

- 516 app unit tests and 72 UI tests, zero failures.
- 16 evaluation-target tests; Debug and Release simulator builds including Watch;
  static analysis; coverage export and built-bundle safety/metadata checks passed.
- Repository Python checks: 57 script tests, 41 scorer tests, 13 summary tests;
  HostEval 247 tests with 36 explicit private-evidence skips; accounting helper
  24 tests. No provider calls or credential access were used.
- All 417 executable/test/build inputs match the frozen SHA-256 manifest after
  validation. Only documentation/accounting changed afterward.
- `git diff --check` and changed-document local-link checks passed.

Private complete evidence: `/private/tmp/pp209-verified-gate.log` and
`/private/tmp/pp209-verified-gate/`, including both result bundles and coverage.
Earlier interrupted/failed iteration runs are not the passing complete receipt.

Focused review caught and repaired a landscape status-detail truncation and an
export UI assertion that needed to scroll to the Share button. The export test,
exercise presentation tests and all ten landscape state captures then passed.
Inspection of the portrait override/ending and landscape interrupted/applying
captures confirmed wrapped product text, distinct status labels and visible
landscape controls. The shortened Bluetooth-delivery sentence is fully visible.
Private synthetic captures are in `/private/tmp/pp209-ui-attachments` and
`/private/tmp/pp209-layout-attachments`; they are not device acceptance.

The dedicated watchOS 26.5 / Watch SE 3 40 mm simulator rendered the initial,
uncertain, known not-saved and zero-interval discard messages from synthetic
journals using the unchanged Watch view. The inspected captures show wrapped
message text within the screen width; controls extend below the viewport in its
existing scroll view. These are partial render checks, not an interactive
scroll/VoiceOver pass. The UI automation surface could not select Simulator;
a later saved-cleanup capture was blank/partial and is not counted as layout
acceptance. Private evidence is `/private/tmp/pp209-watch-*.png`; no image contains
operator health data. The task-owned Watch simulator was shut down afterward. Synthetic unit
and UI evidence is distinct from paired-device HealthKit acceptance. UI tests
exercise accessible labels/values and large text; they are not a VoiceOver user
session. Watch screen layout is a scroll view; inspect text fit separately from
native Health saving. No physical treadmill operation, provider request or release
upload belongs to this slice.

#210 remains responsible for moving support tools out of ordinary navigation;
#211 for confirmation-flow changes. #115/#212 retain repeated/background/recovery
device acceptance; #116 retains treadmill acceptance; WeeklyHealthReport #80
retains downstream extraction acceptance. Build 21 operator success is not evidence
that this unreleased copy has been installed on devices.
