{
  inputs = {
    # @NOTE: Using different releases of nixpkgs to install and test against different
    #  versions of supported clients (grafana, prometheus alertmanager). This list will
    #  expand as time passes and new releases should be pinned as well as flake lockfile
    #  updated to test against latest versions on unstable channel. Note, that versions
    #  of the programs below are written as of the date on this comment and might be
    #  inaccurate, especially for the unstable channel.
    #                                                            - andrew, May 6 2026
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"; # Grafana v13.0.1+, Prometheus v3.11.3+
    nixpkgs-25-11.url = "github:NixOS/nixpkgs/nixos-25.11"; # Grafana v12.3.6, Prometheus v3.7.2
    nixpkgs-25-05.url = "github:NixOS/nixpkgs/nixos-25.05"; # Grafana v12.0.7, Prometheus v3.5.0
    nixpkgs-24-11.url = "github:NixOS/nixpkgs/nixos-24.11"; # Grafana v11.3.7+security-01, Prometheus v2.55.0
    nixpkgs-24-05.url = "github:NixOS/nixpkgs/nixos-24.05"; # Grafana v10.4.14, Prometheus v2.54.1
    nixpkgs-23-05.url = "github:NixOS/nixpkgs/nixos-23.05"; # Grafana v9.5.15, Prometheus v2.44.0
    flake-parts.url = "github:hercules-ci/flake-parts";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crane.url = "github:ipetkov/crane";
  };

  outputs = inputs @ {
    flake-parts,
    nixpkgs,
    nixpkgs-25-11,
    nixpkgs-25-05,
    nixpkgs-24-11,
    nixpkgs-24-05,
    nixpkgs-23-05,
    crane,
    self,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux" "aarch64-linux"];
      perSystem = {
        config,
        self',
        inputs',
        pkgs,
        system,
        ...
      }: let
        grafana-to-ntfy = let
          craneLib =
            (crane.mkLib pkgs).overrideToolchain
            inputs.fenix.packages.${system}.minimal.toolchain;
        in
          craneLib.buildPackage {
            src = craneLib.cleanCargoSource ./.;
          };

        # @NOTE: Healthcheck uses a shell script so it can read ROCKET_PORT at runtime,
        #  defaulting to 8080. This requires bash in the image (pulled in via writeShellScriptBin).
        healthcheck = pkgs.writeShellScriptBin "healthcheck" ''
          ${pkgs.curl}/bin/curl -sf "http://0.0.0.0:''${ROCKET_PORT:-8080}/health"
        '';

        docker-image = pkgs.dockerTools.buildLayeredImage {
          name = "grafana-to-ntfy";
          tag = grafana-to-ntfy.version;
          contents = [grafana-to-ntfy pkgs.cacert pkgs.curl healthcheck];
          config = {
            Entrypoint = ["${grafana-to-ntfy}/bin/grafana-to-ntfy"];
            Env = [
              "ROCKET_PORT=8080"
              "ROCKET_ADDRESS=0.0.0.0"
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
            ExposedPorts = {"8080/tcp" = {};};
            Healthcheck = {
              Test = ["CMD" "${healthcheck}/bin/healthcheck"];
              Interval = 10000000000; # 10s
              Timeout = 3000000000; # 3s
            };
          };
        };
      in {
        formatter = pkgs.alejandra;

        devShells.default = let
          pythonCustom =
            pkgs.python3.withPackages
            (ps: with ps; [websocket-client]);
        in
          with pkgs;
            mkShell {
              RUST_LOG = "info";
              buildInputs = [
                inputs.fenix.packages.${system}.complete.toolchain
                alejandra
                bore-cli
                cargo-audit
                deadnix
                pythonCustom
                act # for testing gh workflows locally
              ];
            };

        packages = {
          inherit grafana-to-ntfy;
          default = grafana-to-ntfy;
          docker = docker-image;
        };

        checks = let
          checkArgs = versioned-pkgs: {
            inherit pkgs;
            inherit system;
            inherit versioned-pkgs;
            inherit grafana-to-ntfy;
          };
          dockerCheckArgs = versioned-pkgs:
            (checkArgs versioned-pkgs) // {inherit docker-image;};
        in {
          grafana-base-test-unstable = import ./tests/grafana-base-test.nix (checkArgs nixpkgs);
          grafana-base-test-25-11 = import ./tests/grafana-base-test.nix (checkArgs nixpkgs-25-11);
          grafana-base-test-25-05 = import ./tests/grafana-base-test.nix (checkArgs nixpkgs-25-05);
          grafana-base-test-24-11 = import ./tests/grafana-base-test.nix (checkArgs nixpkgs-24-11);
          grafana-base-test-24-05 = import ./tests/grafana-base-test.nix (checkArgs nixpkgs-24-05);
          grafana-base-test-23-05 = import ./tests/grafana-base-test.nix (checkArgs nixpkgs-23-05);
          # @TODO: Legacy Grafana (v8.x on nixos-22.05) uses a different alerting API and requires
          #  a separate test config. Re-add nixpkgs-22-05 input when implementing.
          #  See: https://grafana.com/docs/grafana/v8.5/http_api/alerting_notification_channels/#test-notification-channel
          # grafana-base-test-22-05 = import ./tests/grafana-base-test.nix (checkArgs nixpkgs-22-05);
          # @NOTE: Docker test only needs one nixpkgs version — the image is the same binary
          #  regardless of which Grafana/Prometheus version connects to it.
          grafana-docker-test-unstable = import ./tests/grafana-docker-test.nix (dockerCheckArgs nixpkgs);
          prometheus-base-test-unstable = import ./tests/prometheus-base-test.nix (checkArgs nixpkgs);
          prometheus-base-test-25-11 = import ./tests/prometheus-base-test.nix (checkArgs nixpkgs-25-11);
          prometheus-base-test-25-05 = import ./tests/prometheus-base-test.nix (checkArgs nixpkgs-25-05);
          prometheus-base-test-24-11 = import ./tests/prometheus-base-test.nix (checkArgs nixpkgs-24-11);
          prometheus-base-test-24-05 = import ./tests/prometheus-base-test.nix (checkArgs nixpkgs-24-05);
          prometheus-base-test-23-05 = import ./tests/prometheus-base-test.nix (checkArgs nixpkgs-23-05);
          # @TODO: Legacy Prometheus (v2.35 on nixos-22.05) may need separate config for older Alertmanager API.
          #  Re-add nixpkgs-22-05 input when implementing.
          # prometheus-base-test-22-05 = import ./tests/prometheus-base-test.nix (checkArgs nixpkgs-22-05);
          failure-test-unstable = import ./tests/failure-test.nix (checkArgs nixpkgs);
        };
      };
    };
}
