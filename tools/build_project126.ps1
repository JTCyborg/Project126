$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$assembler = Join-Path $root "tools/sjasmplus.exe"
$build = Join-Path $root "build"

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
        Name = "ATM"
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

        # Delete all stale products for this unit before invoking the assembler.
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
        Write-Host "[BUILD] Placement audit: build/$($unit.Listing) ; build/$($unit.Map)"
    }
}
finally {
    Pop-Location
}
