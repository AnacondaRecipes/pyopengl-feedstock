@echo on
REM Windows build (64-bit only: win-64 / win-arm64, no cross).
REM
REM The PyPI sdist ships prebuilt VC9/VC10 DLLs in OpenGL/DLLS
REM (gle32/64, freeglut32/64). conda-build's overlinking check
REM rejects them because MSVCR90/MSVCR100 are not available.
REM setuptools ships OpenGL/DLLS via data_files=os.listdir(), so
REM pip packages whatever is in OpenGL/DLLS/ at install time.
REM That means the scrub + freeglut copy MUST happen BEFORE
REM `pip install` -- doing it in site-packages afterwards is too
REM late, the legacy DLLs are already in the package.
REM
REM Action order:
REM   1. Build native GLE DLL (gle64/glearm64.vc14.dll) into
REM      OpenGL/DLLS/ in the source tree
REM   2. Scrub legacy VC9/VC10 + sdist VC14 prebuilts from
REM      OpenGL/DLLS/ in the source tree
REM   3. Copy freeglut DLL from conda prefix into OpenGL/DLLS/
REM   4. pip install -- ships only the native GLE DLL, the
REM      conda freeglut DLL, and the GLE license files.

REM Native GLE build. conda-build sets SUBDIR (host_subdir) on
REM every build. win-arm64 and win-64 are both native builds here.
if "%SUBDIR%"=="win-arm64" set "GLE_ARCH=ARM64"
if "%SUBDIR%"=="win-arm64" set "GLE_SUFFIX=arm64"
if "%SUBDIR%"=="win-64" set "GLE_ARCH=X64"
if "%SUBDIR%"=="win-64" set "GLE_SUFFIX=64"
if not defined GLE_ARCH goto :pip
goto :build_gle
:build_gle
echo Building native %GLE_SUFFIX% GLE DLL from GLE 3.1.0 sources in build env...
REM The GLE source is extracted into a named subfolder of the work dir
REM by meta.yaml's `folder: gle-3.1.0`. SRC_DIR == work_dir, so the
REM correct path is %SRC_DIR%\gle-3.1.0 (not a sibling).
set "GLE_DIR=%SRC_DIR%\gle-3.1.0"
if not exist "%GLE_DIR%\src" (
  echo ERROR: GLE sources not found at %GLE_DIR%
  echo SRC_DIR=%SRC_DIR%
  dir /b "%SRC_DIR%"
  exit /b 1
)
echo Using GLE sources at %GLE_DIR%
copy /y "%GLE_DIR%\ms-visual-c\config.h" "%GLE_DIR%\config.h" || exit /b 1
copy /y "%GLE_DIR%\ms-visual-c\config.h" "%GLE_DIR%\src\config.h" || exit /b 1
mkdir "%GLE_DIR%\gle-build" 2>nul
pushd "%GLE_DIR%\gle-build" || exit /b 1
REM Compile GLE sources (exclude the ex_*.c examples). /MT = static CRT
REM, matching conda vc14_runtime (VCRUNTIME140).
cl /nologo /c /O2 /DWIN32 /D_WINDLL /Gd /MT "%GLE_DIR%\src\*.c" || exit /b 1
link /NOLOGO /DLL /MACHINE:%GLE_ARCH% /OUT:gle%GLE_SUFFIX%.vc14.dll /EXPORT:gleExtrusion /EXPORT:gleGetNumSides /EXPORT:gleSetJoinStyle /EXPORT:glePolyCylinder /EXPORT:gleSpiral /EXPORT:gleSetNumSides /EXPORT:uview_direction /EXPORT:gleScrew /EXPORT:gleHelicoid /EXPORT:gleToroid /EXPORT:gleTextureMode /EXPORT:gleSuperExtrusion /EXPORT:gleLathe /EXPORT:gleGetJoinStyle /EXPORT:glePolyCone /EXPORT:gleTwistExtrusion /EXPORT:uviewpoint opengl32.lib glu32.lib *.obj || exit /b 1
if not exist gle%GLE_SUFFIX%.vc14.dll (echo ERROR: gle%GLE_SUFFIX%.vc14.dll not produced & exit /b 1)
mkdir "%SRC_DIR%\OpenGL\DLLS" 2>nul
copy /y gle%GLE_SUFFIX%.vc14.dll "%SRC_DIR%\OpenGL\DLLS\gle%GLE_SUFFIX%.vc14.dll" || exit /b 1
echo Built gle%GLE_SUFFIX%.vc14.dll into OpenGL/DLLS
popd
if errorlevel 1 exit /b 1
copy /y "%GLE_DIR%\COPYING" "%SRC_DIR%\OpenGL\DLLS\gle_COPYING" 2>nul
copy /y "%GLE_DIR%\src\COPYING.src" "%SRC_DIR%\OpenGL\DLLS\gle_COPYING.src" 2>nul
copy /y "%GLE_DIR%\AUTHORS" "%SRC_DIR%\OpenGL\DLLS\gle_AUTHORS" 2>nul

:pip
REM --- Scrub legacy DLLs from the source tree BEFORE pip install ---
REM setup.py does os.listdir(OpenGL/DLLS) at install time, so pip ships
REM whatever is there. Cleaning the installed site-packages copy after
REM install does nothing -- the legacy DLLs already entered the conda
REM package (and the overlinking check runs on that package). Delete
REM them here, in the source tree, before pip packages them.
echo Removing legacy VC9/VC10 DLLs from source tree OpenGL/DLLS...
for %%F in ("%SRC_DIR%\OpenGL\DLLS\*.vc9.dll") do echo Removing %%F & del /q "%%F" 2>nul
for %%F in ("%SRC_DIR%\OpenGL\DLLS\*.vc10.dll") do echo Removing %%F & del /q "%%F" 2>nul
REM Also delete the VC14 prebuilts shipped in the sdist (gle/freeglut
REM 32/64 vc14) -- we replace them with native conda-built versions.
REM NOTE: do NOT delete gle64.vc14 / glearm64.vc14 here -- those are
REM the natively built DLLs we just copied into OpenGL/DLLS above.
for %%F in ("%SRC_DIR%\OpenGL\DLLS\gle32.vc14.dll") do del /q "%%F" 2>nul
for %%F in ("%SRC_DIR%\OpenGL\DLLS\freeglut32.vc14.dll") do del /q "%%F" 2>nul
for %%F in ("%SRC_DIR%\OpenGL\DLLS\freeglut64.vc14.dll") do del /q "%%F" 2>nul
REM Verify no legacy DLLs remain
dir /b "%SRC_DIR%\OpenGL\DLLS" 2>nul

REM --- Copy freeglut DLL from conda prefix into source OpenGL/DLLS ---
REM The conda freeglut package provides freeglut.dll (and freeglut64.dll
REM on some versions) in %LIBRARY_BIN%. PyOpenGL's loader looks for
REM freeglut<64>.vc14.dll etc. in OpenGL/DLLS/. Copy it there with the
REM expected name so pip ships it and so ctypes can find it at runtime.
echo Copying freeglut DLL from conda prefix...
set "FREEGlut_SRC="
for %%F in ("%LIBRARY_BIN%\freeglut.dll") do if exist "%%F" set "FREEGlut_SRC=%%F"
if not defined FREEGlut_SRC for %%F in ("%LIBRARY_BIN%\freeglut64.dll") do if exist "%%F" set "FREEGlut_SRC=%%F"
if defined FREEGlut_SRC (
  if "%SUBDIR%"=="win-arm64" (
    copy /y "%FREEGlut_SRC%" "%SRC_DIR%\OpenGL\DLLS\freeglutarm64.vc14.dll" || exit /b 1
  ) else (
    copy /y "%FREEGlut_SRC%" "%SRC_DIR%\OpenGL\DLLS\freeglut64.vc14.dll" || exit /b 1
  )
  echo Copied %FREEGlut_SRC% into OpenGL/DLLS
) else (
  echo WARNING: freeglut DLL not found in %LIBRARY_BIN%, GLUT will fall back to system search
  dir /b "%LIBRARY_BIN%" 2>nul | findstr /i freeglut
)

set PIP_NO_CACHE_DIR=1
%PYTHON% -m pip install . -vv --no-deps --no-build-isolation
if errorlevel 1 exit /b 1
