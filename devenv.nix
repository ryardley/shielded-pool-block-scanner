{ pkgs, ... }:

{
  # Everything the RAILGUN local demo needs is provisioned here so the host
  # system stays untouched. Enter with `devenv shell` (or `devenv enter`).
  packages = with pkgs; [
    nodejs_22 # Terminal Wallet requires node >= 20; contract repo builds on 18+
    foundry # anvil + cast
    git
  ];

  # The demo script starts anvil itself and manages its lifecycle, so no
  # devenv services/processes are declared here.

  # Expose the installed Terminal Wallet launcher as a `terminal-wallet-cli`
  # command inside `devenv shell` (the launcher lives in the repo's durable
  # cache, so nothing is installed outside this folder).
  enterShell = ''
    export PATH="$PWD/railgun-cache/bin:$PATH"
  '';
}
