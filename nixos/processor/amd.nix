{ ... }:
{
  hardware.cpu.amd.updateMicrocode = true;

  services.hardware.openrgb = {
    motherboard = "amd";
  };
}
