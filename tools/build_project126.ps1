param(
    [ValidatePattern('^[A-Za-z0-9_-]{1,8}$')]
    [string]$HostName = "proj126",
    [ValidatePattern('^[A-Za-z0-9_-]{1,8}$')]
    [string]$BootName = "boot"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$assembler = Join-Path $root "tools/sjasmplus.exe"
$build = Join-Path $root "build"
$diskImage = Join-Path $root "disk_A.trd"
$diskAssembly = "atm_host/project126_disk.asm"

$units = @(
    @{
        Name = "NeoGS"
        Source = "neogs_sub/x86_cpu_state_assemble.asm"
        Binary = "x86_cpu_state.bin"
        Listing = "NEOGS.lst"
        Map = "NEOGS.map"
        Version = "X86_STATE_ALU_MEMORY v0.8.0"
        MaxBytes = 16384
    },
    @{
        Name = "ATM IPC"
        Source = "atm_host/neogs_ipc_assemble.asm"
        Binary = "ATM_IPC.bin"
        Listing = "ATM.lst"
        Map = "ATM.map"
        Version = "ATM_IPC v0.2.0"
        MaxBytes = 65536
    }
    @{
        Name = "NeoGS IPC"
        Source = "neogs_sub/p126_ipc_assemble.asm"
        Binary = "P126_NGS_IPC.bin"
        Listing = "NEOGS_IPC.lst"
        Map = "NEOGS_IPC.map"
        Version = "NGS_IPC v0.1.0"
        MaxBytes = 65536
    }
)

if (-not (Test-Path $assembler)) {
    throw "Pinned SjASMPlus executable not found: $assembler"
}
New-Item -ItemType Directory -Force $build | Out-Null

Push-Location $root
try {
    foreach ($unit in $units) {
        $source = Join-Path $root $unit.Source
        $binary = Join-Path $build $unit.Binary
        $listing = Join-Path $build $unit.Listing
        $map = Join-Path $build $unit.Map

        if (-not (Test-Path $source)) {
            throw "Assembly translation unit not found: $source"
        }

        Remove-Item -Force -ErrorAction SilentlyContinue $binary, $listing, $map
        if ($unit.Name -eq "NeoGS") {
            Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $build "X86CORE.C"), (Join-Path $build "X86IO.C"), (Join-Path $build "X86ALU.C"), (Join-Path $build "X86DEV.C"), (Join-Path $build "X86EXEC.C")
        }

        Write-Host "[BUILD] Project126 $($unit.Name) assembly"
        Write-Host "[DEBUG] Source: $($unit.Source)"
        Write-Host "[DEBUG] Listing: build/$($unit.Listing)"
        Write-Host "[DEBUG] Symbol map: build/$($unit.Map)"
        if ($unit.Name -eq "NeoGS") {
            # The source exports the resident audit/core plus X86IO and X86ALU overlays
            # via SAVEBIN. The overlays reuse logical ORG 8000h on separate
            # physical pages; do not request a sparse combined --raw image.
            & $assembler --msg=all "--lst=build/$($unit.Listing)" --lstlab=sort "--sym=build/$($unit.Map)" $unit.Source
        } else {
            & $assembler --msg=all "--lst=build/$($unit.Listing)" --lstlab=sort "--sym=build/$($unit.Map)" "--raw=build/$($unit.Binary)" $unit.Source
        }
        if ($LASTEXITCODE -ne 0) {
            throw "SjASMPlus failed for $($unit.Name) with exit code $LASTEXITCODE"
        }

        foreach ($path in @($binary, $listing, $map)) {
            if (-not (Test-Path $path)) {
                throw "Required $($unit.Name) build output was not produced: $path"
            }
        }

        $size = (Get-Item $binary).Length
        if ($size -le 0 -or $size -gt $unit.MaxBytes) {
            throw "Invalid $($unit.Name) audit image size: $size bytes (expected 1..$($unit.MaxBytes))"
        }

        if ($unit.Name -eq "NeoGS") {
            $residentImage = Join-Path $build "X86CORE.C"
            $ioOverlay = Join-Path $build "X86IO.C"
            $aluOverlay = Join-Path $build "X86ALU.C"
            $devOverlay = Join-Path $build "X86DEV.C"
            $execOverlay = Join-Path $build "X86EXEC.C"
            foreach ($image in @($residentImage, $ioOverlay, $aluOverlay, $devOverlay, $execOverlay)) {
                if (-not (Test-Path $image)) {
                    throw "Required split NeoGS image was not produced: $image"
                }
            }
            $residentBytes = (Get-Item $residentImage).Length
            $overlayBytes = (Get-Item $ioOverlay).Length
            $aluOverlayBytes = (Get-Item $aluOverlay).Length
            $devOverlayBytes = (Get-Item $devOverlay).Length
            $execOverlayBytes = (Get-Item $execOverlay).Length
            if ($residentBytes -lt 1 -or $residentBytes -gt 0x4000) {
                throw "X86CORE.C size $residentBytes is outside the 1..16384-byte WIN0 limit."
            }
            if ($overlayBytes -lt 1 -or $overlayBytes -gt 0x1000) {
                throw "X86IO.C size $overlayBytes is outside the 1..4096-byte page-04 overlay profile."
            }
            if ($aluOverlayBytes -lt 1 -or $aluOverlayBytes -gt 0x1000) {
                throw "X86ALU.C size $aluOverlayBytes is outside the 1..4096-byte page-05 overlay profile."
            }
            if ($devOverlayBytes -lt 1 -or $devOverlayBytes -gt 0x1000) {
                throw "X86DEV.C size $devOverlayBytes is outside the 1..4096-byte page-06 overlay profile."
            }
            Write-Host "[BUILD] X86CORE.C resident bytes=$residentBytes / 16384"
            Write-Host "[BUILD] X86IO.C overlay bytes=$overlayBytes / 4096"
            Write-Host "[BUILD] X86ALU.C overlay bytes=$aluOverlayBytes / 4096"
            Write-Host "[BUILD] X86DEV.C overlay bytes=$devOverlayBytes / 4096"
            if ($execOverlayBytes -lt 1 -or $execOverlayBytes -gt 0x4000) {
                throw "X86EXEC.C size $execOverlayBytes is outside the 1..16384-byte page-07 overlay profile."
            }
            Write-Host "[BUILD] X86EXEC.C overlay bytes=$execOverlayBytes / 16384"
        }

        Write-Host "[BUILD] $($unit.Version) audit-bytes=$size"
        Write-Host "[BUILD] Listing bytes=$((Get-Item $listing).Length)"
        Write-Host "[BUILD] Symbol map bytes=$((Get-Item $map).Length)"
    }

    # Assemble stage-0 at its execution address; SAVEBIN emits only code bytes.
    Write-Host "[BUILD] Project126 GS105a stage-0 bootstrap"
    & $assembler --msg=all "--lst=build/P126_BOOTSTRAP.lst" --lstlab=sort "--sym=build/P126_BOOTSTRAP.map" "--raw=build/P126_BOOTSTRAP_AUDIT.bin" "neogs_sub/p126_bootstrap_assemble.asm"
    if ($LASTEXITCODE -ne 0) {
        throw "SjASMPlus failed for Project126 bootstrap with exit code $LASTEXITCODE"
    }
    $bootstrapBinary = Join-Path $build "P126_BOOTSTRAP.bin"
    if (-not (Test-Path $bootstrapBinary)) {
        throw "P126 bootstrap SAVEBIN output was not produced."
    }
    $bootstrapBytes = (Get-Item $bootstrapBinary).Length
    if ($bootstrapBytes -lt 1 -or $bootstrapBytes -gt 256) {
        throw "P126 bootstrap size $bootstrapBytes is outside the supported 1..256 byte ROM-load block."
    }
    Write-Host "[BUILD] P126_GS105A_BOOTSTRAP v0.1.0 bytes=$bootstrapBytes"

    # Build the versioned module directory from the exact overlay binaries.
    # CRC-16/CCITT-FALSE matches the Project126 IPC checksum primitive.
    function Get-P126Crc16([byte[]]$Bytes) {
        [int]$crc = 0xFFFF
        foreach ($value in $Bytes) {
            $crc = $crc -bxor ([int]$value -shl 8)
            for ($bit = 0; $bit -lt 8; $bit++) {
                if (($crc -band 0x8000) -ne 0) {
                    $crc = (($crc -shl 1) -band 0xFFFF) -bxor 0x1021
                } else {
                    $crc = ($crc -shl 1) -band 0xFFFF
                }
            }
        }
        return [uint16]$crc
    }

    $moduleProfiles = @(
        @{ Id = 1; Page = 4; File = "X86IO.C" },
        @{ Id = 2; Page = 5; File = "X86ALU.C" },
        @{ Id = 3; Page = 6; File = "X86DEV.C" },
        @{ Id = 4; Page = 7; File = "X86EXEC.C" }
    )
    [System.Collections.Generic.List[byte]]$moduleManifest = [System.Collections.Generic.List[byte]]::new()
    # Header: "P126", format revision, record count, record size.
    $moduleManifest.AddRange([byte[]](0x50, 0x31, 0x32, 0x36, 1, $moduleProfiles.Count, 8))
    foreach ($profile in $moduleProfiles) {
        $modulePath = Join-Path $build $profile.File
        if (-not (Test-Path $modulePath)) {
            throw "Module manifest input is missing: $modulePath"
        }
        [byte[]]$moduleBytes = [System.IO.File]::ReadAllBytes($modulePath)
        if ($moduleBytes.Length -lt 1 -or $moduleBytes.Length -gt 0x4000) {
            throw "$($profile.File) exceeds one physical 16 KiB overlay page."
        }
        [uint16]$moduleCrc = Get-P126Crc16 $moduleBytes
        $moduleManifest.Add([byte]$profile.Id)
        $moduleManifest.Add([byte]$profile.Page)
        $moduleManifest.Add([byte]1) # pinned module
        $moduleManifest.Add([byte]0) # reserved in format v1
        $moduleManifest.Add([byte]($moduleBytes.Length -band 0xFF))
        $moduleManifest.Add([byte](($moduleBytes.Length -shr 8) -band 0xFF))
        $moduleManifest.Add([byte]($moduleCrc -band 0xFF))
        $moduleManifest.Add([byte](($moduleCrc -shr 8) -band 0xFF))
        Write-Host ("[MODULE] id={0} page={1:X2} bytes={2} crc16={3:X4}" -f $profile.Id, $profile.Page, $moduleBytes.Length, $moduleCrc)
    }
    $manifestPath = Join-Path $build "X86MODS.MF"
    [System.IO.File]::WriteAllBytes($manifestPath, $moduleManifest.ToArray())
    Write-Host "[MODULE] X86MODS.MF bytes=$($moduleManifest.Count) records=$($moduleProfiles.Count)"

    # The TR-DOS image is always rebuilt from scratch. Never keep an old disk
    # image if the assembler or a required project file fails.
    Remove-Item -Force -ErrorAction SilentlyContinue $diskImage
    $diskListing = Join-Path $build "ATM_DISK.lst"
    $diskMap = Join-Path $build "ATM_DISK.map"
    Remove-Item -Force -ErrorAction SilentlyContinue $diskListing, $diskMap

    if (-not (Test-Path (Join-Path $root $diskAssembly))) {
        throw "TR-DOS disk assembly source is missing: $diskAssembly"
    }

    # Generate assembly inputs from the checked-in templates so the BASIC
    # LOAD command and TR-DOS directory entries always use the same names.
    $loaderTemplate = Get-Content -Raw (Join-Path $root "atm_host/boot_loader.asm")
    $loaderGenerated = $loaderTemplate.Replace("proj125", $HostName)
    $generatedLoaderPath = Join-Path $root "atm_host/boot_loader.generated.asm"
    Set-Content -Path $generatedLoaderPath -Value $loaderGenerated -Encoding ASCII

    $diskTemplate = Get-Content -Raw (Join-Path $root $diskAssembly)
    $diskGenerated = $diskTemplate.Replace("@@HOST_NAME@@", $HostName).Replace("@@BOOT_NAME@@", $BootName)
    # Use a repository-relative forward-slash-free filename when invoking
    # SjASMPlus; passing an absolute Windows path causes its fileorg warning.
    $generatedDiskPath = "project126_disk.generated.asm"
    Set-Content -Path $generatedDiskPath -Value $diskGenerated -Encoding ASCII

    Write-Host "[BUILD] Host program: $HostName.C"
    Write-Host "[BUILD] TR-DOS boot file: $BootName.B"
    if ($BootName -cne "boot") {
        Write-Warning "TR-DOS automatic startup requires boot.B (lower-case boot). The selected boot file will need manual launching."
    }
    Write-Host "[BUILD] Creating TR-DOS disk image disk_A.trd"
    & $assembler --msg=all "--lst=build/ATM_DISK.lst" --lstlab=sort "--sym=build/ATM_DISK.map" $generatedDiskPath
    if ($LASTEXITCODE -ne 0) {
        throw "TR-DOS image assembly failed with exit code $LASTEXITCODE"
    }

    foreach ($path in @($diskImage, $diskListing, $diskMap)) {
        if (-not (Test-Path $path)) {
            throw "Required TR-DOS output was not produced: $path"
        }
    }

    $diskBytes = (Get-Item $diskImage).Length
    if ($diskBytes -ne 655360) {
        throw "Unexpected TR-DOS image size: $diskBytes bytes (expected 655360-byte 80-track, 2-side, 16-sector TRD)."
    }

    [byte[]]$disk = [System.IO.File]::ReadAllBytes($diskImage)
    $requiredEntries = @(
        @{ Name = ($BootName.PadRight(8) + "B"); Label = "$BootName.B" },
        @{ Name = ($HostName.PadRight(8) + "C"); Label = "$HostName.C" },
        @{ Name = "X86CORE C"; Label = "X86CORE.C" },
        @{ Name = "X86IO   C"; Label = "X86IO.C" },
        @{ Name = "X86ALU  C"; Label = "X86ALU.C" },
        @{ Name = "X86DEV  C"; Label = "X86DEV.C" },
        @{ Name = "X86EXEC C"; Label = "X86EXEC.C" },
        @{ Name = "X86MODS M"; Label = "X86MODS.M"; ExpectedLength = 39; ExpectedSectors = 1 },
        @{ Name = "P126BOOTC"; Label = "P126BOOT.C" },
        @{ Name = "BIOS1   C"; Label = "BIOS1.C"; ExpectedLength = 8192; ExpectedSectors = 32 },
        @{ Name = "BIOS2   C"; Label = "BIOS2.C"; ExpectedLength = 8192; ExpectedSectors = 32 },
        @{ Name = "COMPAQ  C"; Label = "COMPAQ.C"; ExpectedLength = 8192; ExpectedSectors = 32 }
    )

    foreach ($required in $requiredEntries) {
        [byte[]]$entryName = [System.Text.Encoding]::ASCII.GetBytes($required.Name)
        $found = $false
        for ($offset = 0; $offset -lt (128 * 16); $offset += 16) {
            $match = $true
            for ($i = 0; $i -lt $entryName.Length; $i++) {
                if ($disk[$offset + $i] -ne $entryName[$i]) {
                    $match = $false
                    break
                }
            }
            if ($match) {
                $found = $true
                $sectors = [int]$disk[$offset + 13]
                $length = [int]$disk[$offset + 11] + ([int]$disk[$offset + 12] -shl 8)
                if ($sectors -lt 1 -or $length -lt 1) {
                    throw ("TR-DOS entry {0} has invalid length/sector metadata." -f $required.Label)
                }
                if ($null -ne $required.ExpectedLength -and $length -ne $required.ExpectedLength) {
                    throw ("TR-DOS entry {0} has length {1}; expected {2} bytes." -f $required.Label, $length, $required.ExpectedLength)
                }
                if ($null -ne $required.ExpectedSectors -and $sectors -ne $required.ExpectedSectors) {
                    throw ("TR-DOS entry {0} has {1} sectors; expected {2}." -f $required.Label, $sectors, $required.ExpectedSectors)
                }
                Write-Host ("[TRD] {0}: {1} bytes, {2} sectors" -f $required.Label, $length, $sectors)
                break
            }
        }
        if (-not $found) {
            throw ("Required TR-DOS directory entry is missing: {0}" -f $required.Label)
        }
    }

    $buildDisk = Join-Path $build "disk_A.trd"
    Copy-Item -Force $diskImage $buildDisk
    if ((Get-Item $buildDisk).Length -ne 655360) {
        throw "Copied build/disk_A.trd failed size verification."
    }

    Write-Host "[BUILD] P126_TRDOS_IMAGE v0.1.0 bytes=$diskBytes"
    Write-Host "[BUILD] Disk listing bytes=$((Get-Item $diskListing).Length)"
    Write-Host "[BUILD] Disk map bytes=$((Get-Item $diskMap).Length)"
    Write-Host "[BUILD] TR-DOS image: build/disk_A.trd"
}
finally {
    Pop-Location
}
