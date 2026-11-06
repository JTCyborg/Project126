$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$assembler = Join-Path $root "tools/sjasmplus.exe"
$source = Join-Path $root "neogs_sub/x86_cpu_state_assemble.asm"
$build = Join-Path $root "build"
$binary = Join-Path $build "x86_cpu_state.bin"
$listing = Join-Path $build "NEOGS.lst"
$map = Join-Path $build "NEOGS.map"

if (-not (Test-Path $assembler)) {
    throw "Pinned SjASMPlus executable not found: $assembler"
}
if (-not (Test-Path $source)) {
    throw "Assembly translation unit not found: $source"
}
New-Item -ItemType Directory -Force $build | Out-Null

# Remove stale products first: a failed assembler run must not leave old
# listing/map files that could be mistaken for current output.
Remove-Item -Force -ErrorAction SilentlyContinue $binary, $listing, $map

Push-Location $root
try {
    Write-Host "[BUILD] Project126 NeoGS x86 core assembly"
    Write-Host "[DEBUG] Listing: build/NEOGS.lst"
    Write-Host "[DEBUG] Symbol map: build/NEOGS.map"
    & $assembler --msg=all --lst=build/NEOGS.lst --lstlab=sort --sym=build/NEOGS.map --raw=build/x86_cpu_state.bin neogs_sub/x86_cpu_state_assemble.asm
    if ($LASTEXITCODE -ne 0) {
        throw "SjASMPlus failed with exit code $LASTEXITCODE"
    }

    foreach ($path in @($binary, $listing, $map)) {
        if (-not (Test-Path $path)) {
            throw "Required build output was not produced: $path"
        }
    }

    $size = (Get-Item $binary).Length
    if ($size -le 0 -or $size -gt 262144) {
        throw "Invalid NeoGS image size: $size bytes (expected 1..262144)"
    }

    Write-Host "[BUILD] X86_STATE_ALU_ASSEMBLY v0.5.0 bytes=$size"
    Write-Host "[BUILD] Listing bytes=$((Get-Item $listing).Length)"
    Write-Host "[BUILD] Symbol map bytes=$((Get-Item $map).Length)"
    Write-Host "[BUILD] Address map: $listing ; $map"
}
finally {
    Pop-Location
}
