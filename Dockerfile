# Zigbee2MQTT with native Control4 support, built from the forks:
#   - bharat/zigbee-herdsman        @ control4-prod-10.10.0 (sendRaw; the profile whitelist and interview quirk landed upstream in 10.10.0)
#   - bharat/zigbee-herdsman-converters @ control4-26.115.1 (src/devices/control4.ts, in-tree definition)
#
# Replaces the sed-patch approach entirely: both libraries' dist/ trees are
# compiled from source in a builder stage and swapped into the stock image,
# with loud verification. The external converter is retired; the entrypoint
# disables any legacy copy left in the data dir (reversibly).
#
# Version discipline: the base image pins zigbee-herdsman 10.10.0 and
# zigbee-herdsman-converters 26.115.1; both fork branches are based on
# exactly those versions. The verify step fails the build if the base
# image's pins drift away from the forks' versions.

# ── Stage 1: build both forks from source ────────────────────────────
# Always runs on the native build platform: the output (compiled JS dist
# trees) is architecture-independent, and tsc under QEMU emulation
# crashes with SIGILL on cross-arch builds.
FROM --platform=$BUILDPLATFORM node:22-alpine AS builder

RUN apk add --no-cache git

WORKDIR /build

ARG ZH_REPO=https://github.com/bharat/zigbee-herdsman.git
ARG ZH_REF=control4-prod-10.10.0
ARG ZHC_REPO=https://github.com/bharat/zigbee-herdsman-converters.git
ARG ZHC_REF=control4-26.115.1

RUN git clone --depth 1 --branch "$ZH_REF" "$ZH_REPO" zh && \
    cd zh && corepack pnpm install --frozen-lockfile --ignore-scripts && corepack pnpm run build && \
    node -e "console.log('zh built:', require('./package.json').version)"

RUN git clone --depth 1 --branch "$ZHC_REF" "$ZHC_REPO" zhc && \
    cd zhc && corepack pnpm install --frozen-lockfile --ignore-scripts && corepack pnpm run build && \
    node -e "console.log('zhc built:', require('./package.json').version)" && \
    test -f dist/models-index.json

# ── Stage 2: swap the dists into the stock image ─────────────────────
FROM koenkk/zigbee2mqtt:latest

LABEL org.opencontainers.image.source="https://github.com/bharat/zigbee2mqtt-control4"
LABEL org.opencontainers.image.description="Zigbee2MQTT with native Control4 dimmer/keypad support"

COPY --from=builder /build/zh/dist /tmp/fork/zh-dist
COPY --from=builder /build/zh/package.json /tmp/fork/zh-package.json
COPY --from=builder /build/zhc/dist /tmp/fork/zhc-dist
COPY --from=builder /build/zhc/package.json /tmp/fork/zhc-package.json

RUN set -e; \
    ZH=$(node -e "console.log(require.resolve('zigbee-herdsman/package.json', {paths:['/app']}))" | xargs dirname); \
    ZHC=$(node -e "console.log(require.resolve('zigbee-herdsman-converters/package.json', {paths:['/app']}))" | xargs dirname); \
    echo "zigbee-herdsman at: $ZH"; \
    echo "zigbee-herdsman-converters at: $ZHC"; \
    BASE_ZH=$(node -e "console.log(require('$ZH/package.json').version)"); \
    FORK_ZH=$(node -e "console.log(require('/tmp/fork/zh-package.json').version)"); \
    BASE_ZHC=$(node -e "console.log(require('$ZHC/package.json').version)"); \
    FORK_ZHC=$(node -e "console.log(require('/tmp/fork/zhc-package.json').version)"); \
    echo "herdsman: base=$BASE_ZH fork=$FORK_ZH; converters: base=$BASE_ZHC fork=$FORK_ZHC"; \
    [ "$BASE_ZH" = "$FORK_ZH" ] || { echo "FATAL: herdsman version skew (base $BASE_ZH vs fork $FORK_ZH); rebase the fork"; exit 1; }; \
    [ "$BASE_ZHC" = "$FORK_ZHC" ] || { echo "FATAL: converters version skew (base $BASE_ZHC vs fork $FORK_ZHC); rebase the fork"; exit 1; }; \
    rm -rf "$ZH/dist" "$ZHC/dist"; \
    cp -a /tmp/fork/zh-dist "$ZH/dist"; \
    cp -a /tmp/fork/zhc-dist "$ZHC/dist"; \
    rm -rf /tmp/fork

# ── Verify the swap actually delivered the Control4 support ──────────
RUN set -e; \
    ZH=$(node -e "console.log(require.resolve('zigbee-herdsman/package.json', {paths:['/app']}))" | xargs dirname); \
    ZHC=$(node -e "console.log(require.resolve('zigbee-herdsman-converters/package.json', {paths:['/app']}))" | xargs dirname); \
    grep -q "CUSTOM_CONTROL4_PROFILE_ID" "$ZH/dist/adapter/ember/ezsp/ezsp.js" || { echo "FATAL: whitelist missing from ember adapter"; exit 1; }; \
    grep -q "CUSTOM_CONTROL4_PROFILE_ID" "$ZH/dist/adapter/ezsp/adapter/ezspAdapter.js" || { echo "FATAL: whitelist missing from legacy adapter"; exit 1; }; \
    grep -q "sendRaw" "$ZH/dist/controller/model/endpoint.js" || { echo "FATAL: sendRaw missing from Endpoint"; exit 1; }; \
    grep -q "Control4 device" "$ZH/dist/controller/model/device.js" || { echo "FATAL: interview quirk missing from Device"; exit 1; }; \
    test -f "$ZHC/dist/devices/control4.js" || { echo "FATAL: control4 definition missing from converters"; exit 1; }; \
    grep -qi "c4-zigbee" "$ZHC/dist/models-index.json" || { echo "FATAL: c4-zigbee missing from models index (keys are lowercased)"; exit 1; }; \
    node -e "const d=require('$ZHC/dist/devices/control4.js').definitions; if (!d?.length || d[0].model !== 'C4-Zigbee') { throw new Error('definition load failed'); } console.log('control4 definition loads:', d[0].model, d[0].vendor)"; \
    echo "Verified: whitelist, sendRaw, interview quirk, in-tree C4 definition"

# ── Entrypoint: retire the legacy external converter (reversibly) ────
COPY entrypoint.sh /app/c4/entrypoint.sh
RUN chmod +x /app/c4/entrypoint.sh

ENTRYPOINT ["/app/c4/entrypoint.sh"]
CMD ["/sbin/tini", "--", "node", "index.js"]
