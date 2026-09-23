# Contributor source and build provenance — 2026-09-24

This is a dated checkpoint for the `boggspa/ASFireWire` fork. It prevents old local checkouts and similarly numbered test builds from being mistaken for current source. Verify remote refs again before starting new work.

## Current source base

- `mrmidi/ASFireWire` `main` was `42aee35c50532f020f273ec570ce873877737a8d` when checked on 2026-09-24. It contains PR #135 at `df65d352c1b77a26d7fe7270ff9567b1cd781209` and PR #136 above it.
- `boggspa/ASFireWire` `main` was fast-forwarded to the same `42aee35c` commit on 2026-09-24. Use a fresh fetch of `mrmidi/main` for subsequent comparisons. The older `DICE`, `reconcile-upstream-main-v28`, and April Lychzord checkouts are historical branches, not an implementation base.
- FW-159 tracks device resolution and bring-up convergence. Its current plan keeps the known-good `main` DICE order, reviews the experimental `midi` history selectively, and explicitly disallows merging that divergent branch wholesale. FW-160 and FW-168 record the research; FW-161 through FW-167 split the implementation.

## Historical work preserved without merging it

The following fork refs preserve work that existed only in local checkouts. They are archives, not candidates for direct merge into `main`:

| Fork ref | Remote tip | Original local tip | Preservation |
| --- | --- | --- | --- |
| `archive/2026-04-30/lych2-notarised-v16` | `bd066aff84764ba163b1ff7caaaa2e20b8d94e42` | `5dba000d87de9b05b457a8888325fe830a27d74e` | Six commits; final tree identical to the original. Commit identities use a no-reply address because GitHub rejected publication of a private email. |
| `archive/2026-04-30/lychzord-midas-venice-v16` | `f6498a3afe585ad2c3df7fb5b758907a83eea6e1` | `d3491796d9b396a06c7197292b2f37160fadea00` | Three commits; final tree identical to the original, with the same identity-only rewrite. |
| `archive/2026-06-04/midas-workshop` | `96993f64bf5ddaf0dbfe9e1b4211f91cce48da03` | Same | Old Midas EAP/UI workshop snapshot, explicitly marked "not for upstream" in its commit. |

The local `boggspa/*` feature refs already contain the other older contributor branches. Preserve these archives for reference; forward-port a small, verified change only when it still applies to current `main`.

## Two different artifacts called “Build 5”

The directory named `lychzord2/ASFW-0.3.0-build5` in a September Claude scratchpad is **not** evidence of a build from PR #135. Its surviving dext binary embeds `3dbf86055c7da3a4fbe0cb8d515b627d917d3c02`, branch `chore/remove-adhoc-install-scripts`, and `DIRTY BUILD`, with a 2026-09-18 build timestamp. The app and dext signatures are also dated 2026-09-18. That source was based on upstream `ba9a8405`; the directory has no surviving source repository or manifest. The later `bcbdfb43` signing/rebrand commit is likewise absent from the fork remote and the scratchpad's Git objects. Do not claim this binary is reproducible from a clean commit.

Separately, the 2026-09-22 Midas Venice F24 power-on report in Discord calls the tested build “Build 5” and reports `mrmidi/main` `df65d352` as active. Its transaction trace is useful hardware evidence, but the reporter's actual package has not been inspected here. The September 18 scratchpad binary cannot substantiate that later source claim. Until the reporter's package or embedded build stamp is inspected, keep its `df65d352` attribution as **reported**, not independently verified binary provenance.

The local Alesis diagnostic `0.3.0/6` package from 2026-09-19 is a third lane: it used `bcbdfb43` plus a local architecture patch to collect the MultiMix 12 DICE report. Its higher build number does not make it a successor to the F24 test build. The report proves 14 capture channels, two playback channels and no EAP for that Alesis device; it does not prove audio streaming.

## SCSI signing gate

Chris reported on 2026-09-24 that Apple's entitlement/identifier approval for SCSI is still pending for his signing team. SCSI source and entitlements are present, but an unsigned compile is only a code/build check. Do not describe the SCSI path as approved, distributable, or verified to load under Developer ID until Apple grants the required approval and a signed hardware test passes. This pending SCSI approval is separate from older Lych2 entitlement paperwork; no Apple request identifier for the current SCSI approval has been verified here.

## Open hardware and issue work

The F24 report records the first 40-byte DICE section-directory read at `0xFFFFE0000000` sent at S400 after an S400 Config ROM success. It received `evt_missing_ack` and timed out with zero retries, so geometry was not published. A previous capture succeeded after Config ROM had demoted to S200, but it also read later after reset. Speed and readiness are not isolated by those two runs. Current `main` still has no protocol-register failure feedback into the Config ROM speed policy. Collect comparable dumps before claiming a speed demotion is the fix; test any bounded retry separately from FW-159's device-policy convergence.

The local June `CODEX_HANDOFF.md` describes an earlier DICE-era workflow and must not override the current `main`, FW-159, or the 2026-09-22 Discord guidance.
