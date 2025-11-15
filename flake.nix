{
  description = "A simple UDP syslog to journald forwarder";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      # A function that builds the package for a given `pkgs` instance.
      mkPackage = pkgs: pkgs.stdenv.mkDerivation {
        pname = "udp514-journal";
        version = "0.2.1"; # From Makefile
        src = self;

        buildInputs = with pkgs; [
          pkg-config
          libsystemd
        ];

        installPhase = ''
          runHook preInstall
          install -D -m 0755 udp514-journal $out/bin/udp514-journal
          runHook postInstall
        '';
      };
    in
    {
      # Provide `packages.x86_64-linux.default`, `packages.aarch64-linux.default`, etc.
      packages = nixpkgs.lib.eachDefaultSystem (system: {
        default = mkPackage nixpkgs.legacyPackages.${system};
      });

      # Provide a NixOS module
      nixosModules.default = { config, lib, pkgs, ... }:
        let
          cfg = config.services.udp514-journal;
          pkg = mkPackage pkgs; # Build the package for the host system
        in
        {
          options.services.udp514-journal = {
            enable = lib.mkEnableOption "udp514-journal service";
          };

          config = lib.mkIf cfg.enable {
            systemd.services."udp514-journal" = {
              description = "Forward syslog from network (udp/514) to journal";
              requires = [ "systemd-journald.socket" "udp514-journal.socket" ];
              after = [ "network.target" ];
              wantedBy = [ "multi-user.target" ];

              serviceConfig = {
                Type = "notify";
                Restart = "always";
                ExecStart = "${pkg}/bin/udp514-journal";
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
