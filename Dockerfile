# Build stage: MoonBit only supports x86_64, so build on amd64
FROM --platform=linux/amd64 ubuntu:24.04 AS builder

RUN apt-get update && apt-get install -y curl git build-essential nodejs && rm -rf /var/lib/apt/lists/*

# Install MoonBit CLI
RUN curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
ENV PATH="/root/.moon/bin:$PATH"

WORKDIR /src
COPY . .

# Clone bit dependency
RUN git clone --depth 1 https://github.com/bit-vcs/bit.git ../../bit-vcs/bit

# Build native binary (amd64) and JS bundle
RUN moon update && moon build --release --target native src/cmd/actrun && \
    moon build --release --target js src/cmd/actrun && \
    mkdir -p /out && \
    cp _build/native/release/build/cmd/actrun/actrun.exe /out/actrun-native && \
    node scripts/bundle-js.js && \
    cp dist/actrun.js /out/actrun.js

# Runtime stage: multi-arch
FROM ubuntu:24.04

ARG TARGETARCH

RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

# amd64: use native binary, arm64: use Node.js + JS bundle
RUN if [ "$TARGETARCH" = "arm64" ]; then \
      apt-get update && apt-get install -y nodejs && rm -rf /var/lib/apt/lists/*; \
    fi

COPY --from=builder /out/actrun-native /usr/local/bin/actrun-native
COPY --from=builder /out/actrun.js /usr/local/lib/actrun/actrun.js

# Select the right entrypoint based on architecture
RUN if [ "$TARGETARCH" = "amd64" ]; then \
      ln -sf /usr/local/bin/actrun-native /usr/local/bin/actrun; \
    else \
      printf '#!/bin/sh\nexec node /usr/local/lib/actrun/actrun.js "$@"\n' > /usr/local/bin/actrun && \
      chmod +x /usr/local/bin/actrun; \
    fi

ENTRYPOINT ["actrun"]
