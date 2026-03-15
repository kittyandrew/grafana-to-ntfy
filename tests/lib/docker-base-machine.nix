# @NOTE: Docker variant of base-machine.nix. Runs grafana-to-ntfy from the Nix-built
#  Docker image instead of directly as a systemd service. Used to validate the image works.
{
  pkgs,
  ntfy-tester,
  docker-image,
  ...
}: let
  c = import ./config.nix;
in {
  imports = [
    (import ./common-machine.nix {inherit ntfy-tester;})
  ];

  virtualisation.docker.enable = true;

  systemd.services.grafana-to-ntfy-docker = {
    after = ["docker.service"];
    requires = ["docker.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.docker}/bin/docker load < ${docker-image}
      ${pkgs.docker}/bin/docker run -d \
        --name grafana-to-ntfy \
        --network host \
        -e "NTFY_URL=http://${c.host}:${c.ntfy-port}/${c.topic}" \
        -e "BAUTH_USER=${c.user}" \
        -e "BAUTH_PASS=${c.pass}" \
        -e "ROCKET_PORT=${c.gtn-port}" \
        grafana-to-ntfy:${docker-image.imageTag}
    '';
  };
}
