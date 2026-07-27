{ pkgs, ... }:

{
  services.kafka = {
    enable = pkgs.stdenv.hostPlatform.system != "aarch64-darwin";
    connect = {
      enable = true;
    };
  };
}
