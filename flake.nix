# SPDX-FileCopyrightText: 2023 Kerstin Humm <mail@erictapen.name>
#
# SPDX-License-Identifier: GPL-3.0-or-later

{
  description = "Is RE1 late?";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # We needed latest crate2nix for now.
    nixpkgs-crate2nix.url = "github:erictapen/nixpkgs/crate2nix";
  };

  outputs = { self, nixpkgs, flake-utils, nixpkgs-crate2nix }:
    flake-utils.lib.eachSystem
      [ "x86_64-linux" "aarch64-linux" ]
      (system:
        let pkgs = nixpkgs.legacyPackages.${system}; in
        {
          packages = rec {
            server =
              let
                crates = import ./server/Cargo.nix { inherit pkgs; };
              in
              crates.workspaceMembers.isre1late-server.build;
            client = import ./client {
              inherit pkgs;
              inherit icons;
            };
            icons = pkgs.runCommand "icons"
              { nativeBuildInputs = [ pkgs.imagemagick ]; }
              ''
                ${import ./client/icons.nix pkgs}/bin/generate-icons.sh ${./client/icon.svg}

                mkdir -p $out
                cp -R . $out
              '';
            default = server;
          };
          apps = rec {
            server = flake-utils.lib.mkApp { drv = self.packages.${system}.server; };
            default = server;
          };
          checks.reuse = pkgs.runCommand "reuse-check" { } ''
            ${pkgs.reuse}/bin/reuse --root ${self} lint && touch $out
          '';

          devShells.default = pkgs.mkShell {
            buildInputs = with pkgs; [
              # Server
              nodejs
              cargo
              rustc
              diesel-cli
              pkg-config
              openssl
              postgresql
              (import nixpkgs-crate2nix { inherit system; }).crate2nix
              reuse
              (python3.withPackages (ps: with ps; [
                psycopg2
              ]))
              qgis
              websocat
            ] ++

            # Client
            (with pkgs.elmPackages; [
              elm
              elm-format
              elm-test
              elm-json
              elm2nix
              (python3.withPackages (ps: with ps; [ requests ]))

            ]);
            RUST_LOG = "info";
            DATABASE_URL = "postgres://localhost/isre1late?host=/run/postgresql";
            PGDATABASE = "isre1late";
            HAFAS_BASE_URL = "https://v6.vbb.transport.rest";
          };
        }
      ) // {
      nixosModules.default = { config, pkgs, lib, ... }:
        let
          server = self.packages.${config.nixpkgs.localSystem.system}.server;
          client = self.packages.${config.nixpkgs.localSystem.system}.client;
          stateDir = "/var/lib/isre1late";
          inherit (lib) mkEnableOption mkOption mkIf types;
          cfg = config.services.isre1late;
        in
        {

          options.services.isre1late = {
            enable = mkEnableOption "IsRE1late server";
            port = mkOption {
              type = types.int;
              example = 8080;
              description = "TCP port to use.";
            };
            hafasBaseUrl = mkOption {
              type = types.str;
              default = "https://v6.vbb.transport.rest";
              description = "Hafas Base URL without a leading slash.";
            };
          };

          config = mkIf cfg.enable {
            services.postgresql = {
              enable = true;
              ensureDatabases = [ "isre1late" ];
              ensureUsers = [
                {
                  name = "isre1late";
                  ensurePermissions."DATABASE isre1late" = "ALL PRIVILEGES";
                }
              ];
            };

            systemd.services.isre1late = {
              description = "Is RE1 late?";
              after = [ "network.target" "postgresql.service" ];
              requires = [ "postgresql.service" ];
              wantedBy = [ "multi-user.target" ];
              environment = {
                DATABASE_URL = "postgres://localhost/isre1late?host=/run/postgresql";
                HAFAS_BASE_URL = cfg.hafasBaseUrl;
              };

              serviceConfig = {
                Type = "simple";
                ExecStart = ''
                  ${server}/bin/isre1late-server \
                    --port ${builtins.toString cfg.port}
                '';
                Restart = "always";
                RestartSec = "30s";
                StateDirectory = "isre1late";
                User = "isre1late";
                Group = "isre1late";
              };

            };

            users.users.isre1late = {
              isSystemUser = true;
              home = stateDir;
              group = "isre1late";
              packages = [ server ];
            };
            users.groups.isre1late = { };

            services.nginx.enable = true;
            services.nginx.virtualHosts."isre1late.erictapen.name" = {
              enableACME = true;
              forceSSL = true;
              locations = {
                "/".alias = "${client}/";
                "/api".return = "301 /api/";
                "/api/" = {
                  proxyPass = "http://[::1]:${toString cfg.port}";
                  extraConfig = ''
                    proxy_http_version 1.1;
                    proxy_set_header Upgrade $http_upgrade;
                    proxy_set_header Connection upgrade;
                  '';
                };
              };
            };

          };
        };
    };
}
