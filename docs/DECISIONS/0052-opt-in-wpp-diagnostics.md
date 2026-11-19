# ADR-0052: Add opt-in classic WPP diagnostics (patch 0042)

- Status: accepted
- Date: 2026-11-19
- Symptom (V): after patch 0041, a local `rdpsnd` fixture reaches `waveOutWrite`, but a
  real Windows session still produces no sound. The live trace shows successful ACM
  codec probes and no playback stream, conversion, or `waveOutWrite`. MSTSC emits no
  relevant `OutputDebugStringW` failure, so the failure occurs inside its RDP audio
  channel before data reaches Wine's audio APIs.
- Cause (V/I): MSTSC uses classic ETW/WPP for its detailed channel diagnostics. Wine
  registers these providers but never enables them, and `TraceMessage` is a stub. This
  hides the event ID and error arguments needed to distinguish RDPSND negotiation from
  dynamic-channel or server-policy failures.
- Decision: when and only when Wine's `wpp` debug channel is enabled, notify classic
  providers with `WMI_ENABLE_EVENTS`, report all enable flags at verbose level, return a
  synthetic logger handle, and log each `TraceMessage` event number and its bounded
  argument data. Default Wine behavior is unchanged.
- Privacy: WPP arguments can contain sensitive session data. The facility remains
  opt-in through `MSTSC_WINE_TRACE=+wpp`, and raw traces must not be published.
- Risk/rollback: enabling `+wpp` executes provider control callbacks that Wine normally
  leaves dormant and produces a large log. Do not enable it for normal use. Roll back
  patch 0042 if a provider callback destabilizes diagnostic sessions.
- Tests: `tests/static/wpp-trace` registers a synthetic classic provider and emits event
  42 with one DWORD argument. Unmodified Wine leaves the provider disabled; patched Wine
  with `+wpp` invokes the callback and logs the event and bounded argument.
