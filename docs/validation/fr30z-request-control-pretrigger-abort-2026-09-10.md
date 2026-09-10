# FR30z Request Control pre-trigger abort — 10 September 2026

Status: aborted preparation under GitHub issue [#51](https://github.com/syamaner/paceprompt-ios/issues/51). No FTMS Control Point procedure was submitted. This is not Request Control evidence and does not authorise another attempt or any other command.

## Authority and preparation

- The operator explicitly authorised one new Request Control procedure while present at the identified Reebok FR30z, with the deck clear, belt stationary, and console and safety key immediately accessible.
- The candidate started from exact `origin/main` `c4fa7bb85bcf4e858bdc587a46ccaa6b83542122`, which includes the reviewed callback-order policy from issue #72.
- The adopted Bluetooth SIG Fitness Machine Service 1.0.1 and Fitness Machine Profile 1.0.1 revisions, both dated 1 October 2024, remained the checked protocol authority.
- The existing installed app retained the consumed first-attempt gate. To preserve its unrelated local data, preparation used a temporary, uncommitted second one-shot gate generation rather than deleting the app. The same hard allow-list still admitted only exact Request Control byte `00` and consumed the allowance before forwarding.
- All 67 focused codec, transport, diagnostic-gate and presentation tests passed on the temporary candidate. A signed Debug iPhone build then succeeded and was installed over the existing app without deleting its data.

## Sanitised physical-session evidence

- Equipment: operator-identified Reebok FR30z. No treadmill firmware or dongle revision was inferred.
- Central: operator's paired iPhone using built-in Bluetooth. Raw device and peripheral identifiers are deliberately excluded from Git.
- The operator reported that the diagnostic reached **Ready for one request** after connecting to the identified FR30z.
- Before the operator enabled the final confirmations or triggered the send action, the diagnostic process terminated unexpectedly with signal 9.
- The retained raw console capture contains no issue #51 diagnostic records or Request Control submission line. Its sparsity cannot independently prove the final Bluetooth state or absence of traffic.
- The available evidence cannot identify why the process received signal 9. It does not distinguish an OS termination, development-tool termination, operator action or another cause, so the cause remains explicitly unknown.
- The operator explicitly confirmed that the app was disconnected, no Request Control was sent, and no treadmill movement occurred.
- The abort ended the physical-session authority. The app was not relaunched and the FR30z was not reconnected. No compensating command was attempted.

## Safety cleanup and conclusion

- Without launching it, the signed Debug build was replaced on the iPhone by a signed Release build, in which the issue #51 diagnostic is compiled out. Existing app data was preserved.
- The temporary second gate generation and its test were reverted locally and are not part of the repository candidate.
- No `0x2AD9` write, ATT result, Control Point indication or procedure outcome was obtained. Request Control remains unresolved.
- No target-speed, target-inclination, Start, Stop, Pause, Reset, retry, reconnect, workout, provider, HealthKit or Watch operation occurred.
- Issue #51 remains open and tracker #48 remains unchanged. A future physical attempt would require a new, separately reviewed preparation and fresh operator authority.
