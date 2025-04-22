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

ARG USERNAME=root
ARG USERID=0

RUN test ${USERID} -ne 0 && \
    groupadd -g ${USERID} ${USERNAME} && \
    useradd -l -r -u ${USERID} -g ${USERNAME} ${USERNAME}

USER ${USERNAME}

ENV PATH=$PATH:/opt/avh-fvp/bin

CMD ["/bin/bash"]
