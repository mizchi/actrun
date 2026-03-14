FROM ubuntu:24.04 AS builder

RUN apt-get update && apt-get install -y curl git && rm -rf /var/lib/apt/lists/*

# Install MoonBit CLI
RUN curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
ENV PATH="/root/.moon/bin:$PATH"

WORKDIR /src
COPY . .

# Clone bit dependency
RUN git clone --depth 1 https://github.com/bit-vcs/bit.git ../../bit-vcs/bit

RUN moon update && moon build --release --target native src/cmd/actrun

FROM ubuntu:24.04

RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

COPY --from=builder /src/_build/native/release/build/cmd/actrun/actrun.exe /usr/local/bin/actrun

ENTRYPOINT ["actrun"]
