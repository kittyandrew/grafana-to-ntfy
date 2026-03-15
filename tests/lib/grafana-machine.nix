{
  pkgs,
  system,
  ntfy-tester,
  versioned-pkgs,
  grafana-to-ntfy,
  docker-image ? null,
  ...
}: let
  c = import ./config.nix;
  base =
    if docker-image != null
    then import ./docker-base-machine.nix {inherit pkgs ntfy-tester docker-image;}
    else import ./base-machine.nix {inherit pkgs ntfy-tester grafana-to-ntfy;};
in {
  imports = [base];

  services.grafana = {
    enable = true;
    package = versioned-pkgs.legacyPackages.${system}.grafana;
    settings = {
      security.secret_key = "test-only-dummy-key";
      # @NOTE: Disable jitter to eliminate the ~5s random delay before first rule evaluation.
      "unified_alerting".disable_jitter = "true";
    };
    provision = {
      alerting = {
        rules.settings = {
          apiVersion = 1;
          groups = [
            {
              orgId = 1;
              name = "my_rule_group_2";
              folder = "my_first_folder_2";
              interval = "10s";
              rules = [
                {
                  uid = "my_id_2";
                  title = "my_first_rule_2";
                  condition = "A";
                  for = "0s";
                  labels.team = "sre_team1";
                  data = [
                    {
                      refId = "A";
                      datasourceUid = "__expr__";
                      model = {
                        conditions = [
                          {
                            evaluator = {
                              params = [0];
                              type = "gt";
                            };
                            operator.type = "and";
                            query.params = ["A"];
                            reducer.type = "last";
                            type = "query";
                          }
                        ];
                        datasource = {
                          type = "__expr__";
                          uid = "__expr__";
                        };
                        expression = "1==1";
                        intervalMs = 1000;
                        refId = "A";
                        type = "math";
                      };
                    }
                  ];
                }
              ];
            }
          ];
        };

        contactPoints.settings = {
          apiVersion = 1;
          contactPoints = [
            {
              orgId = 1;
              name = "cp_webhook_rec";
              receivers = [
                {
                  uid = "cp_webhook";
                  type = "webhook";
                  disableResolveMessage = false;
                  settings = {
                    url = "http://${c.host}:${c.gtn-port}";
                    httpMethod = "POST";
                    username = c.user;
                    password = c.pass;
                  };
                }
              ];
            }
          ];
          deleteContactPoints = [
            {
              orgId = 1;
              uid = "";
            }
          ];
        };

        policies.settings = {
          apiVersion = 1;
          policies = [
            {
              orgId = 1;
              receiver = "cp_webhook_rec";
              group_by = ["..."];
              group_wait = "0s";
              group_interval = "10s";
              repeat_interval = "1m";
            }
          ];
        };
      };
    };
  };
}
