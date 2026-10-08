{
  description = "Roc to .NET shared-library demonstration";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      # Pin the compiler's binary checksum as well as its nightly tag: the Roc
      # API and generated ABI glue must agree with the compiler used for apps.
      rocArchive = pkgs.fetchurl {
        url = "https://github.com/roc-lang/nightlies/releases/download/nightly-2026-10-04-130536d/roc_nightly-linux_x86_64-2026-10-04-130536d.tar.gz";
        hash = "sha256-iTyG0toKTDkMvb1CWM5F1obl7BW0Lu64Ef0axEU3cU8=";
      };
      roc = pkgs.stdenvNoCC.mkDerivation {
        pname = "roc-nightly";
        version = "2026-10-04-130536d";
        src = rocArchive;
        # The downloaded executable expects ordinary Linux shared-library paths.
        # Rewrite them to Nix-store dependencies without rebuilding the compiler.
        nativeBuildInputs = [ pkgs.autoPatchelfHook ];
        buildInputs = [ pkgs.stdenv.cc.cc.lib pkgs.zlib ];
        dontBuild = true;
        installPhase = ''
          mkdir -p "$out/bin"
          find . -type f -name roc -exec cp {} "$out/bin/roc" \;
          chmod +x "$out/bin/roc"
        '';
      };
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = [ roc pkgs.zig_0_16 pkgs.dotnet-sdk_10 ];
      };
    };
}
