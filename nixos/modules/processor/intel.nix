{
  nixos.modules."processor-intel" =
    { ... }:
    {
      hardware.cpu.intel.updateMicrocode = true;
    };
}
