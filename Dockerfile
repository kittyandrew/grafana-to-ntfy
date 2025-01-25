# Do a cross compile to save time (rather than running in Qemu)
FROM --platform=$BUILDPLATFORM ghcr.io/rust-cross/cargo-zigbuild:0.19.7 AS builder
ARG architecture=x86_64-unknown-linux-musl
WORKDIR /usr/src/app
# Copying config/build files.
COPY src src
COPY Cargo.toml .
COPY Cargo.lock .

# Get the build tools
RUN rustup target add ${architecture}

# Building the program.
RUN cargo zigbuild --locked --release --target ${architecture}

# Create the final image (this must be done with qemu emulation if cross-compiling).
ARG TARGETPLATFORM
FROM --platform=$TARGETPLATFORM docker.io/alpine:3.21.2 AS main
ARG architecture=x86_64-unknown-linux-musl
WORKDIR /usr/src/app
RUN apk add --no-cache curl
# Copying compiled executable from the 'builder'.
COPY --from=builder /usr/src/app/target/${architecture}/release/grafana-to-ntfy .
# Copying rocket config file into final instance (startup/runtime config).
COPY Rocket.toml .
# Running binary.
ENTRYPOINT ["./grafana-to-ntfy"]

# Additional layer for the healthcheck inside the container. This allows us to
# display a container status in the 'docker ps' (or any other docker monitor).
HEALTHCHECK --interval=10s --timeout=3s \
  CMD curl -sf 0.0.0.0:8080/health || exit 1
