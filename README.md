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
| [bharat/zigbee-herdsman](https://github.com/bharat/zigbee-herdsman) | `control4-prod-11.2.0` | Profiles `0xC25C` and `0xC25D` whitelisted, `Endpoint.sendRaw` (bare-APS transmit), an interview quirk so C4 devices pair with a clean interview |
| [bharat/zigbee-herdsman-converters](https://github.com/bharat/zigbee-herdsman-converters) | `control4-26.125.0` | `src/devices/control4.ts`: the full device definition (light, 48-value action enum incl. paddles, LED color control, runtime device-type detection with self-heal) |

With this image, C4 devices show **native support** in the Z2M frontend,
pair with a **successful interview**, and need no external converter. The
entrypoint disables any legacy `control4.mjs` left in the data directory
(reversibly, by renaming it to `.disabled`).

The Home Assistant side lives in
[bharat/homeassistant-control4-zigbee](https://github.com/bharat/homeassistant-control4-zigbee)
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

## Upgrade notes

### Builds from 2026-11-10 onward: real model names (one-way database change)

Control4 devices now report their real model and firmware version
(C4-APD120, C4-KD120, C4-KC120277, C4-SW120277) instead of the generic
`C4-Zigbee`. The first time each device reports its identity, Zigbee2MQTT
**rewrites that device's stored `modelID` and firmware version in
`database.db`**, and records an extra endpoint (2) that carries the identity
reports. Home Assistant then shows the real model names.

This is one-way. An older image does not recognize the new model IDs, so
rolling back the image alone leaves C4-SW120277 relays (and possibly other
devices) unsupported until they are re-paired. Before pulling:

1. Note the digest you're running now:
   `docker inspect --format '{{index .RepoDigests 0}}' <your z2m container>`
2. Stop Zigbee2MQTT and back up `database.db` from its data directory
   (copying the whole data directory is simplest).
3. Pull and start the new image.

To roll back, stop Zigbee2MQTT, restore the backed-up `database.db`, and
start the image by the digest you noted.

### Builds from 2026-11-09: outlet support, fewer select entities

- The C4-V-ROSW120 outlet is supported (on/off relay plus its button).
- The `select.*_effect` and `select.*_power_on_behavior` entities are no
  longer created for Control4 devices; Home Assistant may list the old ones
  as unavailable until you remove them.

## Tags

| Tag | Meaning |
| --- | --- |
| `latest` | Tracks `main`; rebuilt weekly against the upstream base |
| `c4forks` | Transition alias of `latest` (kept while deployments still pin it) |
| `<sha>` | Immutable build anchors, use for rollback |

## History

This image succeeds an earlier approach that patched the compiled herdsman
JS with `sed` and injected an external converter at container start (see
homeassistant-control4-zigbee issue
[#104](https://github.com/bharat/homeassistant-control4-zigbee/issues/104)
for the full journey). The fork-build approach replaced it once the
converter was ported in-tree and the interview quirk landed.
