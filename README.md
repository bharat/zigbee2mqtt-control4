# zigbee2mqtt-control4

A drop-in replacement for the stock `koenkk/zigbee2mqtt` Docker image with
**native support for Control4 Zigbee dimmers and keypads** (C4-APD120,
C4-KD120, C4-KC120277).

```
docker pull ghcr.io/bharat/zigbee2mqtt-control4:latest
```

## What it does

Control4 in-wall devices carry LED control, button events and device
identification over a proprietary ASCII protocol on custom Zigbee profile
`0xC25C`, which stock zigbee-herdsman drops. This image rebuilds two
libraries from forks and swaps them into the stock image:

| Fork | Branch | Adds |
| --- | --- | --- |
| [bharat/zigbee-herdsman](https://github.com/bharat/zigbee-herdsman) | `control4-prod` | Profile `0xC25C` whitelist, `Endpoint.sendRaw` (bare-APS transmit), an interview quirk so C4 devices pair with a clean interview |
| [bharat/zigbee-herdsman-converters](https://github.com/bharat/zigbee-herdsman-converters) | `control4` | `src/devices/control4.ts`: the full device definition (light, 48-value action enum incl. paddles, LED color control, runtime device-type detection with self-heal) |

With this image, C4 devices show **native support** in the Z2M frontend,
pair with a **successful interview**, and need no external converter. The
entrypoint disables any legacy `control4.mjs` left in the data directory
(reversibly, by renaming it to `.disabled`).

The Home Assistant side lives in
[bharat/homeassistant-control4-dimmers](https://github.com/bharat/homeassistant-control4-dimmers)
(HACS integration: Lovelace chassis editor, button event entities, LED
config services).

## Pairing tip

When pairing a C4 device, scope Z2M's permit-join to a strong Zigbee router
**physically near the device** (a mains smart plug works well). Both
unscoped permit-join and joins scoped to a distant router reliably fail:
the device attempts association, flashes its orange retry pattern, and
gives up. Factory reset is top-tap x4 (or the full 13-4-13 sequence).

## Build guarantees

The build fails loudly rather than shipping a broken image:

- **Version-skew assertion**: the fork versions must exactly match the
  herdsman/converters versions pinned by the upstream base image. When
  upstream bumps them, the weekly rebuild fails until the forks are rebased.
- **Content verification**: the whitelist (both EZSP adapters), `sendRaw`,
  the interview quirk, the control4 definition, and its models-index entry
  are all grepped/loaded post-swap.

## Tags

| Tag | Meaning |
| --- | --- |
| `latest` | Tracks `main`; rebuilt weekly against the upstream base |
| `c4forks` | Transition alias of `latest` (kept while deployments still pin it) |
| `<sha>` | Immutable build anchors, use for rollback |

## History

This image succeeds an earlier approach that patched the compiled herdsman
JS with `sed` and injected an external converter at container start (see
homeassistant-control4-dimmers issue
[#104](https://github.com/bharat/homeassistant-control4-dimmers/issues/104)
for the full journey). The fork-build approach replaced it once the
converter was ported in-tree and the interview quirk landed.
