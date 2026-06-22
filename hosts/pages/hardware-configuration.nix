{ ... }: {
  # placeholder — replaced by nixos-anywhere-generated hardware config
  boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_blk" ];
  nixpkgs.hostPlatform = "x86_64-linux";
}
