# PacePrompt privacy policy

Effective 4 October 2026. This policy covers the PacePrompt iPhone app and its
Apple Watch companion maintained in the
[PacePrompt project](https://github.com/syamaner/paceprompt-ios).

## Data on your devices

PacePrompt uses Bluetooth treadmill readings, your workout plans and your actions
to display and run workouts. Saved plans, treadmill profiles, local workout
history and recovery records stay in the app's protected local storage. This
includes workout times, planned and executed intervals, speed, inclination and
available treadmill distance observations. The app excludes its owned sensitive
stores from device backup. It does not provide cloud sync or a developer-operated
account or server for this information.

PacePrompt contains no advertising or analytics SDK and does not sell your data
or track you across apps or websites. Troubleshooting reports and workout JSON
leave the app only when you deliberately share them. Review the content and the
chosen destination before sharing; the destination controls any copy it receives.

## Apple Health and Watch recording

The iPhone does not read your Apple Health data. For an iPhone-only workout, you
choose whether to save it to Apple Health. If you choose Watch recording, the
Watch requests the relevant Health permissions, reads available heart-rate and
active-energy information and saves the Watch-owned workout with its execution
intervals and available accepted treadmill distance. The iPhone cannot separately
save that same attempt. A workout without usable execution intervals is not
saved, although sensor samples may already remain in Apple Health.

The Health record may include workout times, duration, heart-rate and estimated
energy statistics, interval targets and observations, distance and recording
metadata. Availability depends on your permissions and what HealthKit produces.
PacePrompt does not send your HealthKit records or local workout history to an AI
provider. Apple Health controls its own storage and any synchronisation you enable;
PacePrompt does not write these records to an app-managed iCloud store.

You can change PacePrompt's Health permissions in Apple's Health/privacy settings.
Removing PacePrompt’s local app data does not delete workouts or sensor samples
from Apple Health. Individual history deletion is not available in this version;
manage Health records separately in Apple Health. Other apps
can read a saved Health workout only under the permissions you give them; their
handling of your data is covered by their policies.

## Optional remote workout import

You can use the app without remote import. Each remote request requires a
separate disclosure and your agreement. If you proceed, the workout text you
entered is sent to OpenRouter and the selected OpenAI service to produce a plan
for your review. This is an external service using your own OpenRouter account
and key. Do not enter information you do not want those services to receive.
The request does not automatically attach your local history, HealthKit data or
Bluetooth diagnostic captures.

Your key is stored in this device's non-synchronising Keychain and is sent only
to the authorised provider endpoint for the request. The app does not log the key
or include it in workout exports. Request processing is subject to
[OpenRouter's privacy policy](https://openrouter.ai/privacy) and the applicable
[OpenAI business terms](https://openai.com/policies/business-terms/). The services
receive network and account information needed to process requests. PacePrompt
does not promise zero provider retention or control copies already received by a
provider. Use their account/privacy controls for retention or deletion requests.

Declining the request prevents that transfer. In Settings → OpenRouter key you
can delete the stored key; revoking it in OpenRouter also prevents its future use.
Cancelling a request cannot recall information already transmitted.

## Retention, deletion and your choices

Saved plans and treadmill profiles can be removed through their available app
controls. Individual workout-history deletion is not available in this version;
history and recovery records remain until the app’s local data is removed on the
respective device. Recovery records protect against duplicating an uncertain
Health save; starting a new workout does not prove an older record was erased. Delete the stored remote key separately before
removing the app, because Keychain items can outlive an installation.

PacePrompt's developer does not receive a copy of your local workout database and
cannot remotely erase it, your Health records, or files you shared elsewhere.
Remove shared files at their destination. Stop using optional remote import and
revoke the key to withdraw that access; use Apple settings to withdraw Bluetooth
or Health permissions. These choices may make the corresponding feature
unavailable without requiring you to create a PacePrompt account.

Apple's TestFlight distribution and any feedback you deliberately submit are
handled by Apple under its own terms and privacy controls. Opening this policy
uses your browser to visit GitHub; normal website/network information is then
handled by GitHub. The app does not append workout information to that link.

## Questions and changes

For non-sensitive questions, use the
[project issue tracker](https://github.com/syamaner/paceprompt-ios/issues).
Do not post health records, credentials or device identifiers in a public issue.
We update this policy when the app's handling of data changes; the effective date
above identifies this version. A policy update does not grant the app permission
to perform a Health save, share, or remote request on your behalf.
