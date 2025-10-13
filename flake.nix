{
  description = "Build Keelung with GHC 9.8.4";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=25.05";
  };

  outputs = { self, nixpkgs }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };
    packageName = "keelung";
    galois-field-src = (pkgs.fetchFromGitHub {
      owner = "Zekt";
      repo = "galois-field";
      rev = "c4a6445aa7d1f73098a5f5c4a98aec8f0f679c1c";
      sha256 = "sha256-xG1L9erSivihqpOt8j2i6D13cZCZJmVD6cFfRBy0V2E=";
    });
	  h = pkgs.haskell.packages.ghc984.extend (self: super: {
        poly = pkgs.haskell.lib.dontCheck super.poly;
        galois-field = pkgs.haskell.lib.doJailbreak (self.callCabal2nix "galois-field" galois-field-src {});
      });
    keelung = pkgs.haskell.lib.dontCheck (h.callCabal2nix packageName ./. {});
	  x = h.callCabal2nix packageName rec {};
  in {
    packages.${packageName} = h.keelung;
    packages.${system}.default = h.keelung;
    pacakges.default = self.packages.${system}.default;
    devShells.${system}.default = pkgs.mkShell {
      buildInputs = [
        (h.ghcWithPackages (hpkgs: [ keelung ]))
        h.haskell-language-server
        # h.cabal-install
      ];
    shellHook = ''
      zsh
    '';
    };
  };
}
