# Create and start a Hyper-V test VM for the T3 ISO. Run in an Administrator PowerShell:
#   powershell -ExecutionPolicy Bypass -File C:\Users\tawin\T3OS\live\make-vm.ps1
$ErrorActionPreference = "Stop"
$name = "T3-Test"
$iso  = Get-ChildItem "C:\Users\tawin\T3OS\build\t3-*-amd64.iso" | Sort-Object LastWriteTime | Select-Object -Last 1
$dir  = "C:\Users\tawin\T3OS\vm"
if (-not $iso) { throw "No ISO found in C:\Users\tawin\T3OS\build" }
if (Get-VM -Name $name -ErrorAction SilentlyContinue) {
  # existing VM: put the newest ISO in its DVD drive and boot from it first
  if ((Get-VM -Name $name).State -ne "Off") { Stop-VM -Name $name -TurnOff -Force }
  $dvd = Get-VMDvdDrive -VMName $name
  if (-not $dvd) { Add-VMDvdDrive -VMName $name -Path $iso.FullName; $dvd = Get-VMDvdDrive -VMName $name }
  else { Set-VMDvdDrive -VMName $name -ControllerNumber $dvd.ControllerNumber -ControllerLocation $dvd.ControllerLocation -Path $iso.FullName }
  Set-VMFirmware -VMName $name -FirstBootDevice (Get-VMDvdDrive -VMName $name)
  Write-Host "VM $name now boots from $($iso.Name)"
} else {
  New-Item -ItemType Directory -Force $dir | Out-Null
  New-VM -Name $name -Generation 2 -MemoryStartupBytes 6GB -NewVHDPath "$dir\t3-test.vhdx" `
         -NewVHDSizeBytes 60GB -SwitchName "Default Switch" -Path $dir | Out-Null
  Set-VM -Name $name -ProcessorCount 4 -StaticMemory -CheckpointType Disabled
  Set-VMFirmware -VMName $name -SecureBootTemplate MicrosoftUEFICertificateAuthority
  Add-VMDvdDrive -VMName $name -Path $iso.FullName
  Set-VMFirmware -VMName $name -FirstBootDevice (Get-VMDvdDrive -VMName $name)
  Write-Host "Created VM $name from $($iso.Name)"
}
if ((Get-VM -Name $name).State -ne "Running") { Start-VM -Name $name }
vmconnect localhost $name
