
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

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

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

# Use the container's C++ runtime for the GDBServer plugin.
RUN case "$(dpkg --print-architecture)" in \
        arm64) libstdcpp=/usr/lib/aarch64-linux-gnu/libstdc++.so.6 ;; \
        amd64) libstdcpp=/usr/lib/x86_64-linux-gnu/libstdc++.so.6 ;; \
        *) exit 1 ;; \
    esac && \
    ln -s "${libstdcpp}" /opt/avh-fvp/libstdc++-preload.so

# Make the bundled SDL2 library discoverable by its soname when the archive
# contains the fully versioned file (observed in the Arm64 release).
RUN if test -f /opt/avh-fvp/bin/libSDL2-2.0.so.0.3000.0; then \
        case "$(dpkg --print-architecture)" in \
            arm64) libdir=/usr/lib/aarch64-linux-gnu ;; \
            amd64) libdir=/usr/lib/x86_64-linux-gnu ;; \
            *) exit 1 ;; \
        esac && \
        ln -s /opt/avh-fvp/bin/libSDL2-2.0.so.0.3000.0 \
            "${libdir}/libSDL2-2.0.so.0"; \
    fi

# VIO Python scripts use the native getch module. Keep it outside the system
# Python installation so it is available to the FVP's embedded interpreter.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        python3-dev \
        python3-pip && \
    python3 -m pip install --no-cache-dir --target /opt/fvp-python 'getch==1.0'

ARG USER
ARG USERID

RUN test "${USERID}" -ne 0 && \
    groupadd -g "${USERID}" "${USER}" && \
    useradd -l -r -u "${USERID}" -g "${USER}" "${USER}"

USER "${USER}"

ENV PATH="${PATH}:/opt/avh-fvp/bin"
ENV PYTHONPATH=/opt/fvp-python
ENV AVH_FVP_PLUGINS=/opt/avh-fvp/plugins
ENV LD_PRELOAD=/opt/avh-fvp/libstdc++-preload.so

CMD ["/bin/bash"]
