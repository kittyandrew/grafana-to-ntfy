FROM clux/muslrust as builder
WORKDIR /usr/src/app
# Copying config/build files.
COPY src src
COPY Cargo.toml .
COPY Cargo.lock .
# Building the program.
RUN rustup target add x86_64-unknown-linux-musl \
 && cargo install --locked --target x86_64-unknown-linux-musl --path .


FROM alpine:3.14 as main
WORKDIR /usr/src/app
RUN apk add --no-cache curl
# Copying compiled executable from the 'builder'.
COPY --from=builder /root/.cargo/bin/grafana-to-ntfy .
# Copying rocket config file into final instance (startup/runtime config).
COPY Rocket.toml .
# Running binary.
ENTRYPOINT ["./grafana-to-ntfy"]


# Additional layer for the healthcheck inside the container. This allows us to
# display a container status in the 'docker ps' (or any other docker monitor).
HEALTHCHECK --interval=10s --timeout=3s \
  CMD curl -sf 0.0.0.0:8080/health || exit 1
