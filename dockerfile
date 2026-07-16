
# hadolint global ignore=DL3008,DL3015
FROM ubuntu:22.04

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
    add-apt-repository -y ppa:deadsnakes/ppa && \
    apt-get install -y --no-install-recommends libpython3.9 x11-apps xterm telnet

ARG FVP_VERSION
ARG FVP_BASE_URL
ARG FVP_ARCHIVE

RUN curl -LO ${FVP_BASE_URL}/${FVP_VERSION}/${FVP_ARCHIVE} && \
    mkdir -p /opt/avh-fvp && \
    tar -xf ${FVP_ARCHIVE} --strip-components 1 -C /opt/avh-fvp && \
    rm ${FVP_ARCHIVE}

ARG TARGETARCH
COPY FVP_plugins/ /tmp/fvp-plugins/
RUN mkdir -p /opt/avh-fvp/plugins && \
    case "${TARGETARCH}" in \
        arm64) plugin_arch=linux_aarch64 ;; \
        amd64) plugin_arch=linux_x86_64 ;; \
        *) echo "Unsupported image architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac && \
    install -m 0755 "/tmp/fvp-plugins/${plugin_arch}/GDBServer.so" \
        /opt/avh-fvp/plugins/GDBServer.so

ARG USERNAME=root
ARG USERID=0

RUN test ${USERID} -ne 0 && \
    groupadd -g ${USERID} ${USERNAME} && \
    useradd -l -r -u ${USERID} -g ${USERNAME} ${USERNAME}

USER ${USERNAME}

ENV PATH=$PATH:/opt/avh-fvp/bin
ENV AVH_FVP_PLUGINS=/opt/avh-fvp/plugins

CMD ["/bin/bash"]
