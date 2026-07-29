Alesis soaks on `dev` + 4 local changes (nub-rate, TX[1] geometry clamp ×2 producers, 3 watchdog cherry-picks). Continuous capture, hardware synth, your MCP health tools.

```
run  build            dur     outcome
1    v53 mixed-rate   13 min  zombie (silent, no fault raised)
2    v54 coherent     60 min  PASS
3    v55 +watchdog    37 min  IT FATAL
4    v55              90 min  IT FATAL   <- longest session yet
5    v55              82 min  PASS (hit deadline)
~2.4h audio captured. All failures auto-recovered.
```

```
# FINDINGS

1  Mid-session interrupt-dispatch stall  (both fatals, byte-identical)
   ctrl     = 0x00008411   run=1 active=1 evt=0x11 ack_complete  (IT healthy)
   intEvent = 0x007000c0   bits 6+7 = isochTx+isochRx LATCHED
   Both are in kBaseIntMask -> controller IS raising them, nothing
   services or clears them. Not a bus fault.
   (bits 20/21/22 = cycleSynch/cycle64Sec/cycleLost are unmasked and
    latch forever - ignore them, I nearly misread them as the cause)
   Time-to-failure 37-90 min, no accumulation pattern.

2  1ms watchdog dies at first bus reset  <- why #1 was invisible
   AsyncWatchdogTimerFired_Impl returns on the lifecycle gate BEFORE
   its own self-reschedule, so one non-Running moment kills it forever.
   Reviving it gave us attribution - and exposed a latent
   _os_unfair_lock_recursive_abort (Poll() holds HardwareAccessScope
   across StopImmediatelyForTxFault()).

3  No teardown after IT FATAL
   Context stops, but CoreAudio keeps consuming inserted zeros
   indefinitely. StopIO never told.

4  Every StartIO after the first hangs until a dext restart
   One shape: ReservePlayback -> kIOReturnNoResources, IRM provably
   clean (4915 units free, only broadcast ch31 held).

5  Cycle master never armed - blocks ALL isoch on this topology
   Mac is root, LinkControl.cycleMaster=0.
   [CyclePolicy] decision=not-bm isRoot=1 bm=63 cycleSeen=0 action=none(0)
   Nothing claims BM on Mac + 1 interface, and roleMode==ClientOnly
   short-circuits before the BM/IRM paths are evaluated.
   FW-22 opt-in (FullBusManager + CyclePolicyAllowed) fixed it instantly:
   TX 48 pkts / 0 IRQs  ->  36,936 pkts / 5,864 IRQs.
```

**Q on #5:** can `ClientOnly` ever carry isoch audio on that topology? Default left alone — the opt-in is uncommitted and correctly fails `CapabilityMode.LiveDefault_IsPassiveClient`.

Findings doc + local patch + full ring history available if useful.
