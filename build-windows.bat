@echo off
setlocal enabledelayedexpansion

rem build-windows.bat - Build Skia for Windows
rem Usage: build-windows.bat [options]
rem Options:
rem   /y               Skip confirmation prompts (useful for CI/automation)
rem   /help            Show this help message

rem Parse arguments
set "NON_INTERACTIVE=false"
:parse_args
if "%~1"=="" goto :done_args
if /i "%~1"=="/y" (
    set "NON_INTERACTIVE=true"
    shift
    goto :parse_args
)
if /i "%~1"=="/help" (
    echo Usage: %~nx0 [options]
    echo Options:
    echo   /y               Skip confirmation prompts
    echo   /help            Show this help message
    exit /b 0
)
echo [ERROR] Unknown option: %~1
exit /b 1

:done_args

echo.
echo ===================================================
echo  Skia Build Script for Windows
echo ===================================================
echo.

rem Get script directory
set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%"

rem Check for Python 3
echo [INFO] Checking for Python 3...
where python >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python not found in PATH
    echo         Please install Python 3.8+ from https://www.python.org/
    exit /b 1
)

rem Verify Python version is 3.x
for /f "tokens=*" %%i in ('python --version 2^>^&1') do set "PYTHON_VER=%%i"
echo [INFO] Found: %PYTHON_VER%

rem Check for Visual Studio
echo [INFO] Checking for Visual Studio...
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
    echo [ERROR] Visual Studio not found.
    echo         Please install Visual Studio 2019 or later with C++ workload.
    exit /b 1
)

for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VS_PATH=%%i"
if "%VS_PATH%"=="" (
    echo [ERROR] Visual Studio C++ tools not found.
    exit /b 1
)
echo [INFO] Found Visual Studio: %VS_PATH%

rem Initialize VS environment
set "VCVARS=%VS_PATH%\VC\Auxiliary\Build\vcvars64.bat"
if not exist "%VCVARS%" (
    echo [ERROR] vcvars64.bat not found
    exit /b 1
)
call "%VCVARS%" >nul 2>&1
echo [INFO] Visual Studio environment initialized

rem Check for Git
where git >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Git not found in PATH
    exit /b 1
)
echo [INFO] Git found

rem Get depot_tools
echo.
echo [STEP 1] Getting depot_tools...
if not exist "depot_tools" (
    git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
    if errorlevel 1 (
        echo [ERROR] Failed to clone depot_tools
        exit /b 1
    )
) else (
    echo [INFO] depot_tools already exists
)

rem Add depot_tools to PATH
set "PATH=%SCRIPT_DIR%depot_tools;%PATH%"

rem Ensure gclient is available (Windows needs .bat extension)
if not exist "depot_tools\gclient.bat" (
    echo [ERROR] depot_tools\gclient.bat not found
    exit /b 1
)

rem Fetch Skia source
echo.
echo [STEP 2] Fetching Skia source...
if not exist "src\skia" (
    mkdir src 2>nul
    cd src

    rem Create .gclient file
    echo solutions = [ > .gclient
    echo   { >> .gclient
    echo     "name": "skia", >> .gclient
    echo     "url": "https://skia.googlesource.com/skia.git", >> .gclient
    echo     "deps_file": "DEPS", >> .gclient
    echo     "managed": False, >> .gclient
    echo   }, >> .gclient
    echo ] >> .gclient

    rem Sync with gclient
    call gclient.bat sync --no-history
    if errorlevel 1 (
        echo [ERROR] Failed to fetch Skia
        cd ..
        exit /b 1
    )
    cd ..
) else (
    echo [INFO] Skia source already exists
)

rem Enter Skia directory
cd src\skia

rem Sync dependencies
echo.
echo [STEP 3] Syncing Skia dependencies...
python tools/git-sync-deps
if errorlevel 1 (
    echo [ERROR] Failed to sync Skia dependencies
    cd ..\..
    exit /b 1
)

rem Fetch ninja
echo.
echo [STEP 4] Fetching ninja...
python bin/fetch-ninja
if errorlevel 1 (
    echo [WARNING] fetch-ninja failed, trying system ninja
)

rem Set output directory
set "RELEASE_NAME=release-windows"
set "OUT_DIR=out\%RELEASE_NAME%"

rem Clean previous build
if exist "%OUT_DIR%" (
    echo [INFO] Removing previous build...
    rmdir /s /q "%OUT_DIR%"
)
mkdir "%OUT_DIR%"

rem Generate args.gn
echo.
echo [STEP 5] Generating build configuration...
set "ARGS_FILE=%OUT_DIR%\args.gn"

echo is_debug = false > "%ARGS_FILE%"
echo is_official_build = true >> "%ARGS_FILE%"
echo target_cpu = "x64" >> "%ARGS_FILE%"
echo skia_use_system_expat = false >> "%ARGS_FILE%"
echo skia_use_system_icu = false >> "%ARGS_FILE%"
echo skia_use_system_libjpeg_turbo = false >> "%ARGS_FILE%"
echo skia_use_system_libpng = false >> "%ARGS_FILE%"
echo skia_use_system_libwebp = false >> "%ARGS_FILE%"
echo skia_use_system_zlib = false >> "%ARGS_FILE%"
echo skia_use_system_harfbuzz = false >> "%ARGS_FILE%"
echo skia_use_system_freetype2 = false >> "%ARGS_FILE%"
echo skia_enable_svg = true >> "%ARGS_FILE%"
echo skia_enable_tools = false >> "%ARGS_FILE%"
echo skia_use_gl = true >> "%ARGS_FILE%"
echo skia_use_vulkan = false >> "%ARGS_FILE%"
echo skia_use_direct3d = false >> "%ARGS_FILE%"
echo skia_use_dawn = false >> "%ARGS_FILE%"
echo extra_cflags_cc = ["/EHsc", "/GR"] >> "%ARGS_FILE%"

echo [INFO] Build configuration:
type "%ARGS_FILE%"

rem Run GN
echo.
echo [STEP 6] Running gn gen...
bin\gn gen %OUT_DIR%
if errorlevel 1 (
    echo [ERROR] gn gen failed
    cd ..\..
    exit /b 1
)

rem Build with ninja
echo.
echo [STEP 7] Building Skia (this may take 15-30 minutes)...
bin\ninja -C %OUT_DIR% skia svg
if errorlevel 1 (
    echo [ERROR] Build failed
    cd ..\..
    exit /b 1
)

rem Return to script directory
cd ..\..

echo.
echo ===================================================
echo  Skia Build Successful!
echo ===================================================
echo.
echo Output directory: %SCRIPT_DIR%src\skia\out\%RELEASE_NAME%
echo.
echo Libraries built:
dir /b "%SCRIPT_DIR%src\skia\out\%RELEASE_NAME%\*.lib" 2>nul
echo.

exit /b 0
