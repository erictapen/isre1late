# SPDX-FileCopyrightText: 2020 Kerstin Humm <mail@erictapen.name>
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
              nodejs
              cargo
              rustc
              diesel-cli
              pkg-config
              openssl
              postgresql
              (import nixpkgs-crate2nix { inherit system; }).crate2nix
              reuse
              python3
              qgis
              websocat
            ];
            RUST_LOG = "info";
            DATABASE_URL = "postgres://localhost/isre1late?host=/run/postgresql";
            PGDATABASE = "isre1late";
          };
        }
      ) // {
      nixosModules.default = { config, pkgs, lib, ... }:
        let
          package = self.packages.${config.nixpkgs.localSystem.system}.server;
          stateDir = "/var/lib/isre1late";
          inherit (lib) mkEnableOption mkOption types;
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
          };

          config = {
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
              after = [ "network.target" ];
              wantedBy = [ "multi-user.target" ];
              environment.DATABASE_URL = "postgres://localhost/isre1late?host=/run/postgresql";

              serviceConfig = {
                Type = "simple";
                ExecStart = ''
                  ${package}/bin/isre1late-server \
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
              packages = [ package ];
            };
            users.groups.isre1late = { };

          };
        };
    };
}
