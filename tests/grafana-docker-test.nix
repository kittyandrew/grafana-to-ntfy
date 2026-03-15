# @NOTE: Same as grafana-base-test.nix but runs grafana-to-ntfy from the Nix-built
#  Docker image to validate the image works end-to-end. The docker-image arg is passed
#  via dockerCheckArgs in flake.nix, which causes grafana-machine.nix to import
#  docker-base-machine.nix instead of base-machine.nix.
(import ./lib/lib.nix) {
  name = "grafana-docker-test";

  nodes = {
    primary = import ./lib/grafana-machine.nix;
  };

  testScript = let
    c = import ./lib/config.nix;
  in ''
    primary.wait_for_unit("docker.service")
    primary.wait_for_unit("ntfy-sh")
    primary.wait_for_open_port(${c.ntfy-port})
    primary.wait_for_unit("grafana-to-ntfy-docker")
    primary.wait_for_open_port(${c.gtn-port})
    primary.wait_for_unit("grafana")
    primary.wait_for_open_port(${c.grafana-port})
    primary.succeed("grafana --version > /tmp/metadata.txt")
    primary.succeed("ntfy-tester-py")
  '';
}
