# @NOTE: Validates failure code paths: auth rejection, ntfy unreachability,
#  and missing NTFY_URL (503 on both health and webhook endpoints).
#  This test does NOT require grafana, prometheus, or ntfy — it only runs
#  grafana-to-ntfy instances to exercise error handling.
(import ./lib/lib.nix) {
  name = "failure-test";

  nodes = {
    primary = {
      pkgs,
      grafana-to-ntfy,
      ...
    }: let
      c = import ./lib/config.nix;
      misconfiguredPort = "8001";
    in {
      environment.systemPackages = [pkgs.curl];

      systemd.services.grafana-to-ntfy = {
        enable = true;
        script = "${grafana-to-ntfy}/bin/grafana-to-ntfy";
        wantedBy = ["multi-user.target"];
        environment = {
          ROCKET_PORT = c.gtn-port;
          # @NOTE: Point to a port where nothing is listening to force POST failure.
          NTFY_URL = "http://${c.host}:19999/nonexistent";
          BAUTH_USER = c.user;
          BAUTH_PASS = c.pass;
        };
      };

      # @NOTE: Second instance with no NTFY_URL to test the misconfigured/unhealthy path.
      systemd.services.grafana-to-ntfy-no-url = {
        enable = true;
        script = "${grafana-to-ntfy}/bin/grafana-to-ntfy";
        wantedBy = ["multi-user.target"];
        environment = {
          ROCKET_PORT = misconfiguredPort;
        };
      };
    };
  };

  testScript = let
    c = import ./lib/config.nix;
    misconfiguredPort = "8001";
  in ''
    primary.wait_for_unit("grafana-to-ntfy")
    primary.wait_for_open_port(${c.gtn-port})
    primary.wait_for_unit("grafana-to-ntfy-no-url")
    primary.wait_for_open_port(${misconfiguredPort})

    # Test 1: Wrong credentials → 401 Unauthorized
    status = primary.succeed(
        "curl -s -o /dev/null -w '%{http_code}' "
        "-u wrong:credentials "
        "-H 'Content-Type: application/json' "
        "-d '{\"status\": \"firing\", \"message\": \"test\"}' "
        "http://${c.host}:${c.gtn-port}"
    ).strip()
    assert status == "401", f"Expected 401 for wrong credentials, got {status}"

    # Test 2: No credentials when auth is required → 401 Unauthorized
    status = primary.succeed(
        "curl -s -o /dev/null -w '%{http_code}' "
        "-H 'Content-Type: application/json' "
        "-d '{\"status\": \"firing\", \"message\": \"test\"}' "
        "http://${c.host}:${c.gtn-port}"
    ).strip()
    assert status == "401", f"Expected 401 for missing credentials, got {status}"

    # Test 3: Correct credentials but ntfy unreachable → 502 Bad Gateway
    # This exercises the most complex failure path: auth passes, request is built
    # (tags, title, priority), ntfy POST fails, error handling returns 502.
    status = primary.succeed(
        "curl -s -o /dev/null -w '%{http_code}' "
        "-u ${c.user}:${c.pass} "
        "-H 'Content-Type: application/json' "
        "-d '{\"status\": \"firing\", \"message\": \"test\"}' "
        "http://${c.host}:${c.gtn-port}"
    ).strip()
    assert status == "502", f"Expected 502 for unreachable ntfy, got {status}"

    # Test 4: Missing NTFY_URL → health returns 503 Service Unavailable
    status = primary.succeed(
        "curl -s -o /dev/null -w '%{http_code}' "
        "http://${c.host}:${misconfiguredPort}/health"
    ).strip()
    assert status == "503", f"Expected 503 for health with no NTFY_URL, got {status}"

    # Test 5: Missing NTFY_URL → webhook returns 503 Service Unavailable
    status = primary.succeed(
        "curl -s -o /dev/null -w '%{http_code}' "
        "-H 'Content-Type: application/json' "
        "-d '{\"status\": \"firing\", \"message\": \"test\"}' "
        "http://${c.host}:${misconfiguredPort}"
    ).strip()
    assert status == "503", f"Expected 503 for webhook with no NTFY_URL, got {status}"
  '';
}
