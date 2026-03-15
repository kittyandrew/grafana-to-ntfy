# @NOTE: Shared test machine config: ntfy-sh service, tester script, and environment
#  variables used by all test variants (direct systemd, Docker, Grafana, Prometheus).
{ntfy-tester, ...}: let
  c = import ./config.nix;
in {
  environment.systemPackages = [ntfy-tester];
  # @NOTE: NTFY_URL here is scheme-less (host:port/topic) because tester.py prepends ws:// itself.
  #  The service-level NTFY_URL (in base-machine/docker-base-machine) includes http:// because
  #  the Rust binary uses it as-is for POST.
  environment.variables = {
    NTFY_URL = "${c.host}:${c.ntfy-port}/${c.topic}";
  };

  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url = "http://${c.host}";
      listen-http = ":${c.ntfy-port}";
    };
  };
}
