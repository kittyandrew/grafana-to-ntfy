{
  inputs = {
    # @NOTE: Using different releases of nixpkgs to install and test against different
    #  versions of supported clients (grafana, prometheus alertmanager). This list will
    #  expand as time passes and new releases should be pinned as well as flake lockfile
    #  updated to test against latest versions on unstable channel. Note, that versions
    #  of the programs below are written as of the date on this comment and might be
    #  inaccurate, especially for the unstable channel.
    #                                                            - andrew, Oct 26 2024
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"; # Grafana v11.2.2+security-01, Prometheus v2.51.0
    nixpkgs-24-05.url = "github:NixOS/nixpkgs/nixos-24.05"; # Grafana v10.4.10, Prometheus v2.51.0
    nixpkgs-23-05.url = "github:NixOS/nixpkgs/nixos-23.05"; # Grafana v9.5.15, Prometheus v2.44.0
    nixpkgs-22-05.url = "github:NixOS/nixpkgs/nixos-22.05"; # Grafana v8.5.15, Prometheus v2.35.0

    flake-parts.url = "github:hercules-ci/flake-parts";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    flake-parts,
    nixpkgs,
    nixpkgs-24-05,
    nixpkgs-23-05,
    nixpkgs-22-05,
    crane,
    self,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux"];
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
            src = ./.;
            nativeBuildInputs = [pkgs.pkg-config];
            buildInputs = [pkgs.openssl];
          };
      in {
        formatter = pkgs.alejandra;

        devShells.default = let
          pythonCustom =
            pkgs.python3.withPackages
            (ps: with ps; [websocket-client requests]);
        in
          with pkgs;
            mkShell {
              RUST_LOG = "info";
              nativeBuildInputs = [pkg-config];
              LD_LIBRARY_PATH = lib.makeLibraryPath [openssl];
              buildInputs = [
                inputs.fenix.packages.${system}.complete.toolchain
                clippy
                rustc
                openssl
                bore-cli
                pythonCustom
                act # for testing gh workflows locally
              ];
            };

        packages = {
          inherit grafana-to-ntfy;
          default = grafana-to-ntfy;
        };

        checks = let
          checkArgs = versioned-pkgs: {
            inherit pkgs;
            inherit system;
            inherit versioned-pkgs;
            inherit grafana-to-ntfy;
          };
        in {
          grafana-base-test-unstable = import ./tests/grafana-base-test.nix (checkArgs nixpkgs);
          grafana-base-test-24-05 = import ./tests/grafana-base-test.nix (checkArgs nixpkgs-24-05);
          grafana-base-test-23-05 = import ./tests/grafana-base-test.nix (checkArgs nixpkgs-23-05);
          # @TODO: Legacy stuff, requires special (separate) config
          #  https://grafana.com/docs/grafana/v8.5/http_api/alerting_notification_channels/#test-notification-channel
          # grafana-base-test-22-05 = import ./tests/grafana-base-test.nix (checkArgs nixpkgs-22-05);
          prometheus-base-test-unstable = import ./tests/prometheus-base-test.nix (checkArgs nixpkgs);
          prometheus-base-test-24-05 = import ./tests/prometheus-base-test.nix (checkArgs nixpkgs-24-05);
          prometheus-base-test-23-05 = import ./tests/prometheus-base-test.nix (checkArgs nixpkgs-23-05);
          # @TODO: Legacy stuff, requires special (separate) config
          # prometheus-base-test-22-05 = import ./tests/prometheus-base-test.nix (checkArgs nixpkgs-22-05);
        };
      };
    };
}
