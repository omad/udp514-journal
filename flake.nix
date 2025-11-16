{
  description = "A simple UDP syslog to journald forwarder";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      rust-overlay,
    }:
    let
      systems = flake-utils.lib.defaultSystems;
    in
    flake-utils.lib.eachSystem systems (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ rust-overlay.overlays.default ];
        };

        udp514-journal-c = pkgs.stdenv.mkDerivation {
          pname = "udp514-journal-c";
          version = "0.2.1"; # From Makefile
          src = self;

          nativeBuildInputs = [
            pkgs.multimarkdown
          ];
          buildInputs = with pkgs; [
            pkg-config
            systemdLibs
          ];

          installPhase = ''
            runHook preInstall
            install -D -m 0755 udp514-journal $out/bin/udp514-journal
            runHook postInstall
          '';
        };

        udp514-journal-go = pkgs.buildGoModule {
          pname = "udp514-journal-go";
          version = "0.0.1";
          src = self;
          sourceRoot = "${self}/go";

          vendorHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
        };

        udp514-journal-rust = pkgs.rustPlatform.buildRustCrate {
          pname = "udp514-journal-rust";
          version = "0.1.0";
          src = self;
          sourceRoot = "${self}/rust";

          cargoLock = {
            lockFile = ./rust/Cargo.lock;
          };

          nativeBuildInputs = with pkgs; [ pkg-config ];
          buildInputs = with pkgs; [ systemdLibs ];
        };

        allPackages = {
          c = udp514-journal-c;
          go = udp514-journal-go;
          rust = udp514-journal-rust;
          default = udp514-journal-c;
        };
      in
      {
        packages = allPackages;

      }
    )
    // {
      # Provide a NixOS module
      nixosModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.services.udp514-journal;
        in
        {
          options.services.udp514-journal = {
            enable = lib.mkEnableOption "udp514-journal service";

            # package = lib.mkOption {
            #   type = lib.types.package;
            #   default = self.packagesallPackages.default;
            #   description = "The udp514-journal package to use.";
            # };
          };

          config = lib.mkIf cfg.enable {
            systemd.services."udp514-journal" = {
              description = "Forward syslog from network (udp/514) to journal";
              requires = [
                "systemd-journald.socket"
                "udp514-journal.socket"
              ];
              after = [ "network.target" ];
              wantedBy = [ "multi-user.target" ];

              serviceConfig = {
                Type = "notify";
                Restart = "always";
                ExecStart = "${cfg.package}/bin/udp514-journal";
                DynamicUser = true;
                ProtectSystem = "full";
                ProtectHome = true;
                PrivateDevices = true;
                NoNewPrivileges = true;
              };
            };

            systemd.sockets."udp514-journal" = {
              description = "Forward syslog from network (udp/514) to journal socket";
              wantedBy = [ "sockets.target" ];
              socketConfig = {
                ListenDatagram = "514";
              };
            };
          };
        };
    };
}
