# ADR-0053: Validate PCM converter stream formats (patch 0043)

- Status: accepted
- Date: 2026-11-19
- Symptom (V): the one-format PCM `rdpsnd` fixture plays, but a real Windows server
  still produces no sound. WPP shows the live server advertising 30 formats. MSTSC
  repeatedly probes them and never sends the client-format response that precedes
  playback in the working fixture.
- Cause (V/I): Wine's built-in PCM converter accepts `ACM_STREAMOPENF_QUERY` for any
  source and destination whose channel, rate, alignment, and bit-depth fields resemble
  PCM, without checking `wFormatTag`. It therefore reports that it can convert the
  server's MPEG-4 AAC (`0xa106`) formats to PCM. MSTSC consequently treats unsupported
  server codecs as playable; this false capability is the observed live-only
  negotiation divergence.
- Decision: require both sides of a PCM-converter stream to use `WAVE_FORMAT_PCM` and
  return `ACMERR_NOTPOSSIBLE` otherwise. Other ACM drivers remain responsible for
  compressed formats.
- Risk/rollback: an application that deliberately passed a mislabeled PCM buffer to the
  PCM driver will now be rejected. That behavior contradicted the driver's advertised
  single-format contract. Roll back patch 0043 if a legitimate non-PCM path is found.
- Tests: `tests/static/msacm-pcm-format` passes a PCM-shaped MPEG-4 AAC source directly
  to the Microsoft PCM ACM driver. Unmodified Wine 11.0 and the pre-patch runtime return
  success; patch 0043 returns `ACMERR_NOTPOSSIBLE`. The same case is covered in Wine's
  `msacm32` conformance test.
