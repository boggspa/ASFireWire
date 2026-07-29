# Alesis MultiMix FireWire — bring-up and the silent TX context

Investigation notes, 2026-07-27. Hardware: Alesis MultiMix 16 FireWire (DICE/TCAT,
GUID `0x00059504000005fe`), Agere FW800 OHCI (`pci11c1,5901`), macOS Tahoe 26,
ASFireWire `dev` @ `4914eca`.

Written to be read in phases.

**Where it ended up (2026-07-28).** Six distinct host-side faults found; five
fixed or worked around and verified on hardware; on mrmidi's dev branch plus
three bench-gated changes, **CoreAudio captured real audio from the MultiMix**
(Phase 5) — 576 IO callbacks, 97 hardware zero-timestamps, ZTS anchored in
44 ms. The blockers, in causal order: profile gate (his fix), cold-start clock
wedge (our seed), no cycle master (FW-22 opt-in), and a capture-geometry
mismatch — the host demanded 14 AM824 slots against a 12-slot wire because a
phantom second device stream is summed into the totals by two independent
cache producers.

Two hypotheses were pursued hard and **disproved** — the descriptor block shape
(3c) and the unconfigured `TX[1]` stream (3f). Both are recorded rather than
deleted, because acting on either would have meant unpicking work that turned
out to be correct.

---

## Phase 0 — where the device started

The MultiMix did not exist as far as macOS was concerned. `EnsureNubForGuid`
rejected it at the profile gate, so no CoreAudio device was ever published and
nothing downstream could be tested.

## Phase 1 — publishing the device

`AlesisMultiMixProfile` added. Geometry taken from the device's own register
dump rather than assumed:

| | streams | pcm | labels |
|---|---|---|---|
| TX[0] (device→host) | iso 1 | 12 | `MIC_LINE_1..LINE_12` |
| TX[1] (device→host) | iso −1 | 2 | `MAIN_IN L`, `MAIN_IN R` |
| RX[0] (host→device) | iso 0 | 2 | `MAIN_OUT L`, `MAIN_OUT R` |

`caps=0x11000006` → supported rates {44100, 48000}. The 14 capture channels are
12 inputs plus the stereo master return, presented to CoreAudio as one
14-channel stream. Device now publishes as **14 in / 2 out**.

## Phase 2 — the cold-start clock bug *(fixed, verified)*

**Symptom.** Every `StartIO` failed with `kIOReturnTimeout` at the clock-lock
poll. Selecting 48 kHz in Audio MIDI Setup reverted to 44.1 kHz after a pause.

**Cause.** The MultiMix powers up locked at 44.1 kHz while its `CLOCK_SELECT`
register still reads `0x0000020c` (48 kHz). On a cold start `AudioDuplexCoordinator`
has no session clock and fell back to a hardcoded `48000U`. `DoWriteClockSelect`
then compared target against readback, saw them equal, and **skipped the write**.
The lock poll then waited for a transition that had never been requested.

This was not an Alesis quirk — any device whose register disagrees with its
actual running rate at cold start could never start at all.

**Fix.** A purely additive `IDuplexDeviceControl::GetCurrentClock()` (default
returns false, so every other adapter is untouched). `DICETcatProtocol` seeds
`selectedClock_` from the live rate in the `ReadGlobalState` reply and reports it.
The coordinator consults it at its two cold-start sites, guarded by
`IsSupportedAudioClockConfig`.

**Verified on hardware:**

```
DICETcatProtocol: seeded selected clock from device live rate 44100 Hz
clock confirmed via active check (status=0x00000101 rate=44100 locked=1)
Device clock stable before isoch start rate=44100 status=0x00000101 reads=3
AudioCoordinator: StartStreaming ok backend=DICE
```

*Open question for review:* the shape of `GetCurrentClock`. An accessor on the
control interface was the smallest change that reached both cold-start sites,
but you may prefer the coordinator to ask the protocol directly.

## Phase 3 — the silent transmit context

With the clock fixed, bring-up runs clean end to end — IRM channel and bandwidth
allocated both directions, RX/TX stream configs programmed, `GLOBAL_ENABLE`
asserted, source lock confirmed, FSM `Running`, both DMA contexts started
`run=1 active=1 dead=0 evt=0x00`. And then:

```
ASFWAudioDevice: initial hardware ZTS timed out after 500 ms
IT: Stopped. Stats: 48 pkts IRQs=0
ASFWAudioDevice: StartIO failed at WaitForInitialHardwareZts: 0xe00002d6
```

The IT context never takes a completion interrupt, so the ring never refills,
so the device never sees a sustained host stream, so it never transmits, so
there is no hardware ZTS to anchor to.

### 3a — two facts that made this hard to see

**The refill watchdog cannot rescue a cold start.** `IsochTransmitContext::Poll()`
has a watchdog for exactly this interrupt silence, but it needs five stall ticks
*and* `state_ == Running`, and `WaitForInitialHardwareZts` tears the stream down
first. Raising the ZTS budget 500 ms → 4000 ms was tested: the watchdog still
never logged, and the timeout still fired. Reverted — it is not a timing problem.

**Nothing called the descriptor dumpers.** `DumpAtCmdPtr` and `DumpDescriptorRing`
already existed and were dead code, so `IRQs=0` was the entire available evidence.
That one line cannot distinguish three causes with opposite fixes:

- CommandPtr parked and every `statusWord` zero → the controller never executed a descriptor
- CommandPtr advanced and statusWords written → descriptors retired, interrupt lost or masked
- cycleTimer not advancing → no isochronous cycles on the bus at all

A `silent-context probe` was added on the anomaly path in `Stop()`, before RUN is
cleared, because clearing RUN destroys the evidence.

### 3b — first cause: the OMI skip address was self-linked *(fixed, verified)*

First probe output:

```
IT: silent-context probe ctl=0x00008400 cmd=0x803dc004 xmitEvent=0x00000000
    xmitMask=0x00000001 intEvent=0x00500000 intMask=0x878783ff
    cycleTimer=0x300d26ad->0x300d28d2
IT: CmdPtr decoded to logicalIdx=0 (packet=0, block=0)
Pkt[0] OMI: ctl=0x02000008 skip=0x803dc000|4  Q0=0x000240a0(spd=2 tag=1 ch=0 tcode=0xa) Q1=len=8
```

Interrupts correctly unmasked (`xmitMask` bit 0, `intMask` bit 6 and bit 31),
cycle timer advancing, context alive and not dead — and **CommandPtr identical to
packet 0's skip address**, with every status word zero.

`IsochTxDmaRing::Prime`/`Refill` pointed each `OUTPUT_MORE_IMMEDIATE`'s skip
address at *its own* descriptor block. The skip address is where the context
resumes when it cannot meet a packet's cycle deadline. Self-linked, that is not
lossless — it is unrecoverable: the context re-evaluates the same packet, whose
deadline is now further past, so it skips again, forever. One legitimate skip on
the start cycle (the context starts mid-cycle) wedges it permanently.

The in-code comment cited Linux `queue_iso_transmit()` as the precedent, but Linux
writes `d[0].branch_address` only when the client explicitly requested a skip
packet; it is otherwise left zero. The ASFW driver that soaked 4 hours on this
same MultiMix pointed it at the **next** packet unconditionally.

**Fix.** Point the skip address at the next packet, so a lost cycle costs one
packet. **Verified:** CommandPtr now advances — `0x803dc004` → `0x803dcbc4`
(packet 0 → packet 47). The context walks the ring.

### 3c — second cause: the ring is walked but nothing retires *(open)*

After 3b the context advances roughly one packet per isochronous cycle, and
**still retires nothing**:

```
IT: silent-context probe ctl=0x00008400 cmd=0x803dc044->0x803dc044
    xmitEvent=0x00000000 xmitMask=0x00000001 intEvent=0x00500000
    intMask=0x878783ff cycleTimer=0x2408e85a->0x2408ea82
IT: ring status sweep retired=0/48 firstRetired=48 xferStatus=0x0000
```

One correction to an earlier reading in this investigation: CommandPtr advancing
by one packet does **not** prove the context is skipping. The OUTPUT_LAST's
`branchAlways` target and the OMI's skip address both point at the next packet,
so both paths look identical in CommandPtr. The real evidence is the status
sweep: with the descriptor region invalidated first, not one packet in the ring
carries a controller-written status word. **The OUTPUT_LAST is never reached.**

Ruled out by direct measurement:

- **Interrupt bits are correct.** Packet 5 (the `kPacketsPerInterrupt = 6` group
  boundary) carries `ctl=0x183c0004` → bits[21:20] = `11` = IRQ_ALWAYS; packet 0
  carries `00` = never. As intended.
- **Interrupt plumbing is byte-identical** to the driver that worked: register
  offsets, `IsoXmitIntMaskSet`/`IntMaskSet` writes, `CaptureInterruptSnapshot`,
  and the `InterruptDispatcher` routing all match. Masks are live at probe time
  (`xmitMask` bit 0, `intMask` bit 6 and bit 31).
- **Cycle master / cycle timer** are fine; the timer advances during the probe.
- **Packet headers are well-formed**: `spd=2 tag=1 ch=0 tcode=0xa sy=0`, and
  `data_length` agrees with the descriptor `reqCount`s.
- **Stale-cache artifact**, by invalidating the descriptor region before the
  sweep. `retired=0/48` survives that.
- **The split payload.** `dev` splits one contiguous payload across the
  `OUTPUT_MORE` and the `OUTPUT_LAST` (`ResolveTwoFragments` halves it when the
  payload sits in a single DMA segment); for the NO-DATA prefill that is an
  8-byte CIP header carried 4 + 4. Tested with the whole payload in the
  OUTPUT_LAST and the OUTPUT_MORE empty (`OM: req=0`, `OL: req=8`): **still
  `retired=0/48`**. Reverted — it changed nothing and was not otherwise
  justified.

- **The descriptor block shape.** This was the leading hypothesis and it is
  **wrong** — recorded here because it would otherwise be retried. `dev` uses
  **Z=4** (`OUTPUT_MORE_IMMEDIATE` + `OUTPUT_MORE` + `OUTPUT_LAST`); the
  known-good driver used **Z=3** (no `OUTPUT_MORE`). Rebuilt with Z=3, so the
  program became structurally identical to the known-good one — `OMI
  ctl=0x02000008`, `OL ctl=0x180c0008 req=8`, skip → next packet,
  `CommandPtr=0x803dc003 (Z=3)`. Result: **still `retired=0/48`**. Reverted.
  The Z=4 block is not the fault and should not be unpicked.

### 3d — the watchdog was dead, and everything it drives with it *(fixed, verified)*

Chased from a line that never appeared. `[TxTick]` is edge-triggered from
`false` and the IT context demonstrably reaches `Running`, yet it never logged —
so `TickIsochTransmit` was never reached at all.

`AsyncWatchdogTimerFired_Impl` returned early when `AdmitsNormalWork()` was
false, **before** the `ScheduleAsyncWatchdog()` call that re-arms the timer.
Since the tick is self-rescheduling, any single non-`kRunning` moment is
permanent: a bus reset (the log shows three) leaves `kRunning`, the tick landing
during it returns without re-arming, and the 1 ms watchdog is dead for the rest
of the session. `ScheduleAsyncWatchdog()` carried the same gate, so nothing
could revive it.

Everything the tick drives died with it — the async transaction timeout tick,
the IR ZTS/payload-writer/TX-SYT telemetry drains, and the IT refill watchdog.
This also explains the standing note in `WatchdogCoordinator` that Zts, TxSyt
and `[PayloadWriter]` had been *"silent for a whole hardware session"*: the
cause was upstream of the `receiveConsumer_` gating suspected there.

**Verified.** Before: no `[TxTick]`, no `[RxDrain]`, ring never refilled. After:

```
[RxDrain] eligible=1 running=1 verbosity=1
[TxTick] polling=1
IT: refill watchdog engaged (no IT interrupts observed; kicks=1 ...)
IT completion delta high-water=2 → 3 → 11 → 18 → 37
[TxPrep] margin=910 … → margin=811 lead=678 late1500=0 wakes=9
```

Reviving the watchdog immediately exposed a latent crash: `Poll()` held an open
`HardwareAccessScope` while calling `StopImmediatelyForTxFault()`, which takes
the same non-recursive lock — `_os_unfair_lock_recursive_abort`, SIGKILL on
every StartIO. That path is only reachable past
`kIrqSilentKickFatalThreshold`, so it had never run while the watchdog was
dead. Fixed in `0ecf0b5`.

### 3e — ROOT CAUSE: no cycle master on the bus *(found, proven)*

Everything above was downstream of this. Read from the driver's own registers
via the MCP control plane, no code change needed:

```
0x0E0  LinkControlSet   0x00100600     cycleMaster=0  cycleTimerEnable=1
0x0E8  NodeID           0xC800FFC1     iDValid=1  root=1  node=1
```

**The Mac is the root node with cycleMaster clear.** Only the root emits cycle
start packets, so the bus had *no isochronous cycles at all*. IT could not
transmit, IR could not receive, both contexts sat `run=1 active=1 dead=0`
forever, no descriptor retired and no interrupt fired.

This also corrects an earlier reading in this document: the cycle **timer**
register advancing proves nothing, because it is driven by the local clock. The
driver's own telemetry had been saying so all along - `cycleSeen=0`.

Why it was never armed:

```
[CyclePolicy] decision=not-bm gen=1 local=1 root=1 irm=0 bm=63 isBM=0 isRoot=1 action=none(0)
```

`CyclePolicyCoordinator::Plan` has two paths to arming cycle master - be the
elected Bus Manager, or be the IRM with the no-BM fallback gate open. On a Mac
plus one audio interface, `bm=63` (nobody claims BM) and the interface is IRM,
so neither path applies. And before either is evaluated, `roleMode ==
ClientOnly` short-circuits at line 116 with `SuppressedByRoleMode`.

`ClientOnly` is a deliberate, documented default (FW-22): *"Becoming a
contender/BM is wire-visible and can reset a bus, so it is a hardware-validation
opt-in rather than the default for an attached audio device."* This is not a bug
to fix - **the opt-in already exists and hardware validation is what it is for.**

Taking it (`RoleMode::FullBusManager` + `FullBMActivityLevel::CyclePolicyAllowed`)
worked first time, with no other change:

```
[BM Election] Local node is IRM; routing CompareSwap through local CSRControl loopback
[BM Election] WON Bus Manager election! (oldValue=0x3F, compareMatched=1)
[CyclePolicy] enable local cycleMaster gen=1
[CyclePolicy] decision=local-cm ... isBM=1 isRoot=1 action=local-cycle-master(1)
0x0E0  LinkControlSet  0x00300600   cycleMaster=1
```

FW-18/19/20 are functional. And the transmit path came alive immediately:

| | packets | IT interrupts |
|---|---|---|
| before | 48 | 0 |
| cycleMaster on, 500 ms window | 5,028 | 816 |
| cycleMaster on, 4 s window | 36,936 | 5,864 |

Sustained ~9k packets/s with interrupts every 6 packets, ring refilling
continuously, no `IT FATAL`. **The transmit side is now healthy.**

This is a bench-only change held uncommitted in `ControllerConfig.hpp`,
deliberately kept out of the branch. The design question for review is whether
an audio device that needs isochronous cycles can ever work under `ClientOnly`
on a bus where nothing else claims BM - which is the common topology for this
driver.

### 3f — both directions flow; the device sends only CIP NO-DATA

With cycle master armed, a receive-side mirror of the IT stop line settled the
next question immediately:

```
IR: Stopped. Stats: 4974 pkts consumer=1
IT: Stopped. Stats: 5022 pkts IRQs=797
```

**The device was transmitting all along.** ~5,000 packets each way in 500 ms,
receive consumer correctly bound. This killed the leading hypothesis from the
previous round - that the unconfigured `TX[1]` stream (`iso=-1`) was stopping the
device transmitting. It is not. Worth recording, because building host-side
multi-stream capture on that hunch would have been days of wasted work.

What the packets contain:

```
[RxSummary] pkts=1554 validCip=1554 framed=0 cadence=0
            tsValid=1554 tsInvalid=0 negAge=176 bigNegAge=6 ztsPublished=0
```

Every consumed packet carries a **valid CIP header** and **zero audio frames**.
The MultiMix transmits CIP NO-DATA and never leaves it.

## Phase 4 — the "NO-DATA deadlock" *(SUPERSEDED — see Phase 5)*

> **2026-07-28 correction.** The conclusion below is **wrong**, and the error
> was mine: the receive consumer's rejection path returns *before* the packet
> counter my `[RxSummary]` reads, so rejected data packets were invisible to
> it. mrmidi's per-packet attribution tool (`asfw_get_audio_stream_health`,
> dev `b09f953`) showed the truth: the device sends data packets unprompted
> and the host was rejecting every one for geometry. The analysis below is
> retained because its *mechanics* (the `allowRecoveredClock` gate, the
> Saffire asymmetry) are accurate — only the premise "the device never sends
> data" is false. See Phase 5.

The host clock anchor is published only when this gate opens
(`DirectAudioReceiveConsumer::ConsumePacket`):

```cpp
if (kZtsPeriodFrames != 0 && result.framesDecoded != 0 &&
    (packetFirstFrame % kZtsPeriodFrames) == 0 && packetHostTicks != 0 &&
    nanosPerSampleQ8 != 0 && clockPublisher_.IsBound() && cadence.established)
```

`framesDecoded` is 0 for every packet, so it never opens, so `StartIO` times out
at `WaitForInitialHardwareZts`.

Going the other way, `PrepareTransmitSlots` sets
`disposition = AmdtpPacketDisposition::Data` only inside the
`allowRecoveredClock` branch, which needs a valid replay entry carrying
`RxSequenceFlags::kValidSyt` - derived from received packets. NO-DATA packets
carry no valid SYT.

**So both ends wait for each other:**

- the device stays in NO-DATA until it locks to host *data*
- the host stays in NO-DATA until the device's cadence establishes

This is not an accident, it is the documented design:

> *"With an unseeded transmit clock the normal AMDTP cadence is preserved but
> every packet carries NO_INFO (SYT=0xffff), matching the reference Saffire seed
> behavior. Set `allowRecoveredClock` only after HAL has accepted the first real
> RX anchor."* — `ASFWAudioDriverPrivate.hpp:314-318`

It holds on the Saffire because, as `IsochService::StartPreparedTransmit` notes,
*"Focusrite happens to transmit unconditionally"*. The MultiMix does not. This is
the same deadlock already described in that comment for the Midas Venice F32:

> *"IT waited for IR cadence, IR cadence waited for device TX, device TX waited
> for host IT."*

That was fixed for IT **start**. IT **data** has the identical shape and is still
deferred.

### Where this needs a decision

Breaking it means the host emitting data packets with a self-generated SYT
during bootstrap, rather than waiting for an RX anchor - i.e. the host being
timing master for its own transmit stream until the device locks, which is what
FFADO's DICE engine does. That is a clock-mastering decision inside the audio
rewrite, so it is written up rather than guessed at.

The experiment that would confirm it: seed the transmit clock free-running from
the rate the device already reports (`Global: clock=LOCKED 44100Hz`), let TX emit
data packets, and see whether the MultiMix leaves NO-DATA. If it does, the
remaining work is choosing the right bootstrap policy rather than finding a bug.

## Phase 5 — dev-branch validation, the geometry rejection, and FIRST CAPTURE
*(2026-07-28, on mrmidi's dev @ `fd2ccdf` at his request)*

mrmidi asked for the checkout to move to dev (his own `AlesisMultiMixProfile`
landed there in `387979a`, plus 15 more commits) and for dev to be tested.
Results, in run order — build lineage: **v48** = stock dev + local signing;
**v49** = + RolePolicy opt-in; **v50** = + cherry-picked `1d4bca4` (clock seed);
**v51–v53** = + the geometry experiment below, uncommitted.

**What his dev does well on the MultiMix (v48):** his profile matches and
publishes 14-in/2-out; his `7ba0672` nub fix advertises {44.1, 48}; when the
device happens to sit at 48 kHz, bring-up locks it cleanly (`notify=LockChg`,
`status=0x00000201`) and runs end to end.

**Phase 2 reproduced on stock dev (v49):** after the activation bus reset put
the device back at 44.1, `PrepareDuplex48k` spun forever — `active check not
yet locked (status=0x00000101 rate=44100), entering mailbox poll` at 200 ms
intervals, ~2,500 DICE records — and `StartIO failed at StartAudioStreaming`.
The same wedge reproduced a second way: a HAL rate change 44.1→48 reported
success at the HAL layer while the device stayed at 44.1 and the driver spun.
His `7ba0672` fixed the advertisement half; the bring-up half still needs the
live-rate seed (`1d4bca4` cherry-picks cleanly onto dev and fixed it, v50).

**Cycle master on dev (v49/v50):** the FW-22 opt-in works identically on dev —
`[BM Election] WON`, `[CyclePolicy] enable local cycleMaster`, LinkControl
`0x00300600`. Two nits: `asfw_get_controller_state` reports
`isCycleMaster: false` while LinkControl bit 21 is set (stale source), and the
MCP plane listens on the app's persisted 8765 while the new default is 8766.

**The skip-address re-grade (v50):** dev still carries the self-linked OMI skip
address, and with cycles present TX ran fine anyway — `5065 pkts IRQs=802`.
So `939efa6` is a latent-robustness fix (a genuinely missed deadline is still
unrecoverable), **not** the Alesis blocker; cycle master was. Honest downgrade
of an earlier claim in this document.

### The real Phase 4: geometry rejection, not a NO-DATA deadlock

His `asfw_get_audio_stream_health` (b09f953) on the v50 run:

```
verdict: geometryMismatch
dataPackets: 3457   geometryMismatch: 3457   noDataPackets: 1560
```

**The device sends data packets unprompted** — the host rejected every one.
My `[RxSummary]` had missed this because the consumer's rejection path returns
before the counter it reads; instrumentation blind spot, now corrected with a
first-occurrence log at the rejection site:

```
[RxGeom] first mismatch: wire dbs=12 vs channels=12 am824Slots=14 payload=400
```

**Wire DBS is 12.** The MultiMix's second device→host entry (`TX[1]`,
`MAIN_IN L/R`, iso=-1) is a phantom — FFADO clamps these models to one stream
for exactly this reason (dice_avdevice.cpp:1682-1695) — but ASFW sums its slots
into the capture totals, so the host demands 14 slots against a 12-slot wire
and `am824Slots != cip->dataBlockSize` rejects every data packet.

Three compounding host-side facts, all now evidenced:

1. `DICETcatProtocol::CacheRuntimeCaps` sums all streams including iso=-1.
2. `DICEDuplexBringupController::CacheRuntimeCaps` is a **second, independent
   producer of the same cache** — clamping one is not enough; the later write
   wins (split-brain observed on v51/v52: endpoint said 12, nub said 14).
3. `DuplexStreamProfile.hpp:270`: in single-capture mode
   `geometry.am824Slots = caps.deviceToHostAm824Slots` (the total) instead of
   stream 0's — the clamped-to-one-stream path inherits the multi-stream sum.

### v53: first captured audio

With both cache producers clamped to stream 0 (bench-only, uncommitted,
`BENCH_DEV_GEOM.patch`) all three numbers agree at 12, and:

```
Core audio hardware ZTS ready sampleFrame=4608      (anchored in 44 ms)
DUPLEX ready rxStarted=1 txStarted=1
input active=1 rate=48000 channels=12 bits=32
STOPIO callbacks=576 zts=97 rxZts=97 writtenEndFrame=153308
IT: Stopped. Stats: 27691 pkts IRQs=4585
```

**StartIO completed and CoreAudio recorded 2.7 s from the MultiMix** — 576 IO
callbacks, 97 hardware zero-timestamps, 153k frames, TX replay absorbing a real
−1816 ppm host/device offset. The capture WAV carries a live ADC noise floor
(−90..−103 dBFS), not digital zeros. First audio through the new architecture
on this device.

The ZTS anchor took **44 ms** — the 500 ms default budget is generous once
geometry matches; every earlier "ZTS timeout" was downstream of the rejection.

### Still open after v53

- **Every StartIO after the first hangs** *(characterized during soak setup,
  2026-07-28 afternoon)*. Fully reproducible across six trials: the first
  StartIO after a dext start works end to end; every subsequent StartIO leaves
  the client blocked in device open until killed. One failure mode captured
  precisely: `[FSM] class=StageFailure cause=ReservePlayback retryable=0
  status=0xe00002be` (kIOReturnNoResources) **with the IRM provably clean**
  (4915 bandwidth units free, only broadcast ch31 held) — an internal resource
  is not released when a session ends or aborts. Cousin of dev `d485c6c`, which
  covers provider loss but not ordinary session teardown. Consequence: any
  soak must hold ONE capture session open for its whole duration; per-segment
  reopen degenerates into a dext-restart loop.
- **Capture discontinuities at IO-buffer boundaries.** In a 9 s pre-soak
  capture of a live 14.7 Hz triangle: 12 steps > 0.2 full-scale, every one
  landing exactly on a 512-frame boundary (= `maxIoFrames`), ~1.3/s. Upstream
  glitches would not align to the host's IO grid, so this is the capture path
  (input ring cursor / ZTS handoff at block edges). Capture *works* but is not
  yet *clean*; the soak quantifies the rate over time.
- **Playback leg:** the duplex pass hit `AudioQueueStart failed` on the tone
  player. Unexplored.
- **The 2 lost channels:** clamping to stream 0 publishes 12 in, dropping
  `MAIN_IN L/R`. Whether those are reachable at all (second stream is iso=-1
  and FFADO says it does not exist) or via device-side TX reprogramming is a
  design question.
- **The clock-wedge poll loop** on dev has no bound and floods the ring at
  ~25 rec/s (~2.5k records per failed StartIO).
- Where the phantom-stream clamp belongs (protocol, bring-up controller, or a
  single shared producer) is the maintainer's call — the split-brain producers
  are arguably the underlying defect.

## Phase 6 — the first soaks (2026-07-28 evening)

Signal: hardware synth into channel 4 (~24 Hz triangle, −19.8 dBFS). Harness:
one continuous ffmpeg capture per soak (a single StartIO — reopening trips the
StartIO defect), 5-minute rotating segments, per-segment analysis (level, pitch,
IO-boundary steps, inserted-zero gaps, silent-channel floor), driver health via
the MCP plane, stall/zombie watchdogs with automatic dext-restart recovery.

### Soak #1 — mixed clocks (v53: wire 44.1 kHz, HAL 48 kHz): FAILED at 13 min

The TX exposure regulator fought the 8.8 % drift in a `rate-mismatch → stall →
healthy` sawtooth with `debtOther` climbing monotonically (34k → 66k frames).
At stream-time 779 s the divergence `d=3268` exceeded `horizon=2400` and the
exposed frame `E` froze at 37,377,608 — **permanently, with no fault raised and
nothing logged**. RX stayed `receivingData` (4.67M packets) while CoreAudio fed
the client exact-zero silence: a fully instrumented zombie, the same shape as
the 2026-07-19 Duet incident. Arguably the top defect found this week: a
silent, unrecoverable stop state.

Also observed in the mixed session only: all 12 capture channels carried the
same smeared signal (V-shaped per-channel LSB skew). Resolved by coherence —
not the desk, and not further chased.

### Soak #2 — coherent clocks (v54: nub follows the session's locked rate): PASSED 60 min

One StartIO held for 3,602 s, 12 segments, zero zombies, zero restarts. Level
−19.8 dBFS, silent-channel floor −105 dB, pitch flat throughout.

Remaining defects, now precisely quantified:

- **Delivery pacing deficit.** Real frame delivery averaged **87.4 % of
  nominal** (44.1k), breathing slowly between 35.7k and 41.1k fr/s over a
  ~35-minute cycle. The shortfall is the *same 44.1/48 ratio again* at its
  best point — one more 48000 assumption survives in the timing chain
  (suspect: ZTS anchor host-time arithmetic).
- **Boundary clicks = the deficit, made audible.** 31,369 discontinuities in
  the hour, essentially all landing exactly on 512-frame (`maxIoFrames`) IO
  block edges, and their rate tracks `deficit ÷ 512` segment by segment
  (6→16→6 per second). They are the block-edge cursor corrections mopping up
  the pacing shortfall.
- **Three hard gaps** of inserted zeros (2.4 / 3.2 / 3.8 ms, all channels,
  not grid-aligned), all during high-delivery phases of the oscillation.

### Soak #3 — 4 hours, launched 19:53 on the same build

Same harness. Purpose: long-horizon stability of the coherent configuration
(does the oscillation stay bounded; do gaps accumulate; does anything freeze).

### Soak #3/#4 addendum — the mid-session deaths are cycle-start loss

Soak #3 (v54) zombied repeatedly with accelerating time-to-death (60 min → 9
min → 17 s across restarts). Rebuilding with the watchdog fixes cherry-picked
(v55 = + `bd9c90b` `070802d` `0ecf0b5`) converted the silent zombies into
attributed fatals. The black-box ring mirror caught one in full:

```
[TxTick] polling=1                                   (session start)
IT: refill watchdog engaged (kicks=1 ctrl=0x00008411 intEvent=0x007000c0)
IT FATAL: interrupt path silent across 16 consecutive watchdog kicks
IT FATAL STOP: RUN cleared and interrupt masked      (~100 ms detect-to-stop)
```

`intEvent` decodes to **cycleLost + cycleInconsistent** latched: the bus's
cycle-start generation itself failed mid-session, starving both isoch
directions. On v54 nothing observed it (the watchdog is dead after the first
bus reset there) — hence zombies; on v55 the watchdog correctly fatals within
~100 ms. Retrospectively, soak #1's probe already showed `intEvent=0x00500000`
(cycleInconsistent) — cycle trouble was present all along.

**No trigger is visible in the ring**: zero bus resets, topology or controller
events in the 900+ records before the failure. Open candidates: Agere FW800
cycle-timer errata under sustained cycle-master duty, or a transient second
cycle master (the MultiMix is IRM-capable; `cycleInconsistent` fits a
dual-master skirmish). Deciding needs wire visibility (FireBug) or errata
knowledge — maintainer's bench.

Two more device-side observations from the mirror, session-scoped:

- **Device state survives our teardowns.** New boots see the previous
  session's isoch channels still programmed and stale ext-lock status; the
  content of TX[0] also bifurcates by session between per-channel direct outs
  and an identical mono feed on all 12 slots at a consistent −30.6 dB (mode
  unknown — device-side). A device power-cycle is the clean next experiment.
- **The device's ARX1 lock flaps continuously** (`lock[none] ↔ lock[ARX1]`
  every few seconds) — its receive-PLL tracking of our TX stream wobbles with
  our pacing oscillation; a live meter of host TX SYT quality.

### The soak-blocking defect list, ranked

1. **Mid-session cycle-start loss** (cycleLost+cycleInconsistent, no visible
   trigger) — kills every long session; variance 17 s – 60 min. Needs wire
   analysis.
2. **Silent TX-exposure freeze past horizon** (no fault, no recovery) — turns
   any sustained drift into a permanent zombie.
3. **Second-and-later StartIO hangs** (`ReservePlayback` kIOReturnNoResources
   with IRM clean) — reconfirmed three more times today, including after a
   cleanly-completed session.
4. **Residual 48 k pacing assumption** — the 87 % delivery / boundary-click
   engine.
5. Rate-change transition cannot move this device (HAL reports success, wire
   stays put) — interacts with 3.
6. Few-ms inserted-zero gaps under recovered delivery — unexplained.

---

## Incidental fixes made along the way

- **IR start readback.** `IsochReceiveContext::Start()` did not log its context
  state after start, so an IR context that refused to run was indistinguishable
  from one that started fine and received nothing.
- **Descriptor dump decoder shifts.** `DumpDescriptorRing` decoded the interrupt
  field as `(ctl >> 18) & 3` and branch as `(ctl >> 16) & 3`; `BuildControl`
  encodes them at 20 and 18. It printed the branch field as `i` and the wait
  field as `b`, so a packet with no interrupt bit printed `i=3` and looked fine.
- **Transmit watchdog tick visibility.** `[TxTick] polling=N`, edge-logged. The
  line whose absence found the dead watchdog.

## Commits

On `local/alesis-multistream-capture`, on top of `origin/dev` @ `4914eca`:

```
2c93d59  feat(audio): summarise why the receive path produced no clock anchor
c566c82  feat(isoch): report what the IR context actually received
0ecf0b5  fix(isoch): release the hardware lock before the TX fatal stop
070802d  fix(sched): keep the 1 ms watchdog armed across non-Running moments
bd9c90b  feat(sched): report whether the transmit watchdog is actually ticking
ad71118  fix(isoch): decode the TX descriptor dump with the shifts it was encoded with
2983741  feat(isoch): explain a TX context that ran without ever taking an interrupt
939efa6  fix(isoch): point the IT skip address at the next packet, not at itself
e920749  feat(isoch): log the IR context state after start, as IT already does
1d4bca4  fix(audio): start at the device's live clock instead of forcing 48 kHz
9cb8585  feat(dice): add Alesis MultiMix FireWire profile so the device publishes
```

1505/1505 passing. Fork point tagged `bench/alesis-tx-alive-20260727`; restore
instructions in `BENCH_RESTORE.md`.

Held uncommitted and bench-only: the `RolePolicy` opt-in in `ControllerConfig.hpp`,
plus local-signing and version bumps. Note that
`CapabilityMode.LiveDefault_IsPassiveClient` **fails** while that opt-in is
applied - correctly, since it pins `MakeLiveDefault()` to ClientOnly/ObserveOnly.
That test was deliberately left alone; it is the guard that stops the bench
setting shipping by accident.

## Open questions for review

1. **The NO-DATA deadlock (Phase 4).** How should the transmit clock bootstrap
   on a device that will not transmit data until it sees host data? The current
   design defers to the RX anchor, which works on the Saffire and cannot work
   here.
2. **Can `ClientOnly` ever carry isochronous audio?** On a Mac plus one
   interface nothing claims BM, so cycle master is never armed and no isoch is
   possible in either direction. See 3e.
3. `GetCurrentClock` shape - accessor on `IDuplexDeviceControl`, or should the
   coordinator ask the protocol directly?
4. `DuplexStreamProfileTests.AlesisModelsClampAdvertisedCaptureStreamsToOne`
   pins the blanket capture-stream clamp. Left alone. Note that `TX[1]` being
   left at `iso=-1` is now known **not** to block the device transmitting, so
   this is a correctness/capability question rather than a blocker.
