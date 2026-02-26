{ config, pkgs, ... }:

{
  # ... other configurations ...

  programs.claude-code.enable = true;

  # Optional: Configure mcp servers if needed
  # programs.claude-code.mcpServers = {
  #   nixos = {
  #     command = "uvx";
  #     args = [ "mcp-nixos" ];
  #   };
  # };

  # ... other configurations ...
}

