param(
    [string]$EnvName = "envcuda126",
    [string]$CudaBuildDir = "build-cuda",
    [string]$CpuBuildDir = "build-cpu",
    [string]$Configuration = "Release",
    [string]$Generator = "Visual Studio 17 2022",
    [string]$Architecture = "x64"
)

$ErrorActionPreference = "Stop"

function Invoke-Process {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )

    Write-Host ">> $FilePath $($Arguments -join ' ')"
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed: $FilePath"
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

Write-Host "Resolving Python executable from conda environment '$EnvName'"
$pythonExe = (& conda run -n $EnvName python -c "import sys; print(sys.executable)")
$pythonExe = $pythonExe.Trim()
if (-not $pythonExe -or -not (Test-Path $pythonExe)) {
    throw "Unable to resolve Python executable for environment '$EnvName'"
}

$cudaBuildPath = Join-Path $repoRoot $CudaBuildDir
$cpuBuildPath = Join-Path $repoRoot $CpuBuildDir

$commonConfigureArgs = @(
    "-G", $Generator,
    "-A", $Architecture,
    "-DPython3_EXECUTABLE=$pythonExe",
    "-DBUILD_PYTHON_MODULE=ON",
    "-DBUILD_COMMON_CUDA_ARCHS=ON"
)

Write-Host "Configuring CUDA build tree"
Invoke-Process -FilePath "cmake" -Arguments (@("-S", $repoRoot, "-B", $cudaBuildPath, "-DBUILD_CUDA_MODULE=ON") + $commonConfigureArgs)

Write-Host "Configuring CPU fallback build tree"
Invoke-Process -FilePath "cmake" -Arguments (@("-S", $repoRoot, "-B", $cpuBuildPath, "-DBUILD_CUDA_MODULE=OFF") + $commonConfigureArgs)

Write-Host "Building Python package artifacts (CPU)"
Invoke-Process -FilePath "cmake" -Arguments @("--build", $cpuBuildPath, "--config", $Configuration, "--target", "python-package")

Write-Host "Building Python package artifacts (CUDA)"
Invoke-Process -FilePath "cmake" -Arguments @("--build", $cudaBuildPath, "--config", $Configuration, "--target", "python-package")

$cpuStage = Join-Path $cpuBuildPath "lib/python_package/open3d/cpu"
$cudaStageRoot = Join-Path $cudaBuildPath "lib/python_package/open3d"
if (-not (Test-Path $cpuStage)) {
    throw "CPU staging directory not found: $cpuStage"
}

Write-Host "Copying CPU python bindings into CUDA staging"
New-Item -ItemType Directory -Force -Path $cudaStageRoot | Out-Null
Copy-Item -Path $cpuStage -Destination $cudaStageRoot -Recurse -Force

$cpuNative = Join-Path $cpuBuildPath "lib/$Configuration/Python/cpu"
$cudaNativeRoot = Join-Path $cudaBuildPath "lib/$Configuration/Python"
if (Test-Path $cpuNative) {
    New-Item -ItemType Directory -Force -Path $cudaNativeRoot | Out-Null
    Copy-Item -Path $cpuNative -Destination $cudaNativeRoot -Recurse -Force
}

Write-Host "Generating pip wheel"
Invoke-Process -FilePath "cmake" -Arguments @("--build", $cudaBuildPath, "--config", $Configuration, "--target", "pip-package")

$wheelDir = Join-Path $cudaBuildPath "lib/python_package/pip_package"
Write-Host "Wheel artifacts available in: $wheelDir"
