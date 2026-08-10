
# hadolint global ignore=DL3008,DL3015
FROM ubuntu:26.04

ARG DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y \
        curl \
        jq \
        libatomic1 \
        software-properties-common

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get install -y --no-install-recommends libpython3.14 x11-apps xterm telnet

ARG FVP_VERSION
ARG FVP_BASE_URL
ARG FVP_ARCHIVE
ARG FVP_SHA256

# Download the official release archive and remove its leading `./` and
# architecture directory while extracting it into the wrapper's stable path.
RUN curl --fail --location --retry 3 \
        --output "/tmp/${FVP_ARCHIVE}" \
        "${FVP_BASE_URL}/${FVP_VERSION}/${FVP_ARCHIVE}" && \
    echo "${FVP_SHA256}  /tmp/${FVP_ARCHIVE}" | sha256sum --check - && \
    mkdir -p /opt/avh-fvp && \
    tar -xzf "/tmp/${FVP_ARCHIVE}" --strip-components=2 -C /opt/avh-fvp && \
    test -x /opt/avh-fvp/bin/FVP_Corstone_SSE-300 && \
    test -f /opt/avh-fvp/plugins/GDBServer.so && \
    chmod 0555 /opt/avh-fvp/plugins/GDBServer.so && \
    rm -f "/tmp/${FVP_ARCHIVE}"

# Use the container's C++ runtime for the plugin on either supported image
# architecture, without hard-coding an AArch64-only system path.
RUN case "$(dpkg --print-architecture)" in \
        arm64) libstdcpp=/usr/lib/aarch64-linux-gnu/libstdc++.so.6 ;; \
        amd64) libstdcpp=/usr/lib/x86_64-linux-gnu/libstdc++.so.6 ;; \
        *) exit 1 ;; \
    esac && \
    ln -s "${libstdcpp}" /opt/avh-fvp/libstdc++-preload.so

ARG USERNAME=root
ARG USERID=0

RUN test ${USERID} -ne 0 && \
    groupadd -g ${USERID} ${USERNAME} && \
    useradd -l -r -u ${USERID} -g ${USERNAME} ${USERNAME}

USER ${USERNAME}

ENV PATH=$PATH:/opt/avh-fvp/bin
ENV AVH_FVP_PLUGINS=/opt/avh-fvp/plugins
ENV LD_PRELOAD=/opt/avh-fvp/libstdc++-preload.so

CMD ["/bin/bash"]
