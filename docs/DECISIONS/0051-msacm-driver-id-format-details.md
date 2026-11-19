# ADR-0051: Accept ACM driver IDs in format-tag queries (patch 0041)

- Status: accepted
- Date: 2026-11-18
- Symptom (V): a Windows RDP server opened its `rdpsnd` channel, but genuine mstsc
  advertised zero audio formats and sent no audio to Wine. Wine's PulseAudio control-panel
  test worked, and mstsc successfully opened and closed a `waveOut` device without ever
  calling `waveOutWrite`.
- Cause (V): mstsc enumerates ACM driver IDs and passes each ID directly to
  `acmFormatTagDetailsW`. Wine 11.0 treated the parameter only as an open `HACMDRIVER`, so
  every query returned `ACMERR_NOTPOSSIBLE`. Native Windows also accepts an
  `HACMDRIVERID` for this API despite the documented parameter type. With no accepted PCM
  format, mstsc answered the server with a zero-format `SNDC_FORMATS` PDU.
- Decision: when `acmFormatTagDetailsW` receives a registered driver ID, temporarily open
  that driver, perform the existing query, and close it before returning. Open driver
  handles and null (all-driver) queries retain their existing paths.
- Alternatives rejected: forcing a format in `winmm`, changing callback timing, enabling
  Wine GStreamer, and changing PulseAudio configuration do not repair mstsc's codec
  enumeration. Those experiments produced no `waveOutWrite` calls.
- Risk/rollback: opening a driver can execute its normal open/close path during a details
  query. That matches the existing all-driver implementation and native observable
  behavior. Roll back patch 0041 if another ACM client regresses.
- Tests: the Wine `msacm32` test now passes an enumerated driver ID directly to
  `acmFormatTagDetailsW` and requires at least one PCM-capable result. The genuine-mstsc
  test `tests/launch/test-audio.sh` connects to a local FreeRDP server-side fixture,
  confirms that mstsc advertises 44.1 kHz stereo PCM, sends a deterministic tone, and
  requires Wine to reach `waveOutWrite`.
