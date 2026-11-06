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
        Version = "X86_STATE_ALU_ASSEMBLY v0.5.0"
        MaxBytes = 262144
    },
    @{
        Name = "ATM IPC"
        Source = "atm_host/neogs_ipc_assemble.asm"
        Binary = "ATM_IPC.bin"
        Listing = "ATM.lst"
        Map = "ATM.map"
        Version = "ATM_IPC v0.1.0"
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

        Write-Host "[BUILD] Project126 $($unit.Name) assembly"
        Write-Host "[DEBUG] Source: $($unit.Source)"
        Write-Host "[DEBUG] Listing: build/$($unit.Listing)"
        Write-Host "[DEBUG] Symbol map: build/$($unit.Map)"
        & $assembler --msg=all "--lst=build/$($unit.Listing)" --lstlab=sort "--sym=build/$($unit.Map)" "--raw=build/$($unit.Binary)" $unit.Source
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
            throw "Invalid $($unit.Name) image size: $size bytes (expected 1..$($unit.MaxBytes))"
        }

        Write-Host "[BUILD] $($unit.Version) bytes=$size"
        Write-Host "[BUILD] Listing bytes=$((Get-Item $listing).Length)"
        Write-Host "[BUILD] Symbol map bytes=$((Get-Item $map).Length)"
    }

    # The TR-DOS image is always rebuilt from scratch. Never keep an old disk
    # image if the assembler or a required project file fails.
    Remove-Item -Force -ErrorAction SilentlyContinue $diskImage
    $diskListing = Join-Path $build "ATM_DISK.lst"
    $diskMap = Join-Path $build "ATM_DISK.map"
    Remove-Item -Force -ErrorAction SilentlyContinue $diskListing, $diskMap

    if (-not (Test-Path (Join-Path $root $diskAssembly))) {
        throw "TR-DOS disk assembly source is missing: $diskAssembly"
    }

    Write-Host "[BUILD] Creating TR-DOS disk image disk_A.trd"
    & $assembler --msg=all "--lst=build/ATM_DISK.lst" --lstlab=sort "--sym=build/ATM_DISK.map" $diskAssembly
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
        @{ Name = "BOOT    B"; Label = "BOOT.B" },
        @{ Name = "PROJ126 C"; Label = "PROJ126.C" },
        @{ Name = "X86CORE C"; Label = "X86CORE.C" }
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
