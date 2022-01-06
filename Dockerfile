# Proper multi-stage build failed. F.
FROM rust:slim-buster
WORKDIR /usr/src/app
# Copying config/build files.
COPY src src
COPY Cargo.toml .
COPY Cargo.lock .
# Install dependencies.
RUN apt-get update \
 && apt-get upgrade -y \
 && apt-get install -qq -y \
    curl \
    musl-tools \
    libssl-dev \
    openssl \
    pkg-config \
 && rustup target add x86_64-unknown-linux-musl
# Building the program.
# RUN cargo install --locked --target x86_64-unknown-linux-musl --path .
RUN cargo install --locked --path .
# Copying rocket config file into final instance (startup/runtime config).
COPY Rocket.toml .
# Running binary.
ENTRYPOINT ["/usr/local/cargo/bin/grafana-to-ntfy"]

# Additional layer for the healthcheck inside the container. This allows us to
# display a container status in the 'docker ps' (or any other docker monitor).
HEALTHCHECK --interval=10s --timeout=3s \
  CMD curl -sf 0.0.0.0:8080/health || exit 1
