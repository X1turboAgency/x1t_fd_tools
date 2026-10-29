@echo off

rem z80as をパスの通った場所にセット。
SET CMD=z80as.exe

SET WDIR=%~dp0
SET SRCDIR=%WDIR%\src
SET RELEASE_DIR=%WDIR%\..\release

cd %SRCDIR%

SET FD_D88_SRC= ^
 value_define.asm^
 fd_d88_define.asm^
 fd_d88_main.asm^
 disk_info.asm^
 runtime.asm^
 cli.asm^
 console.asm^
 iocs_fdd.asm^
 d88_common.asm^
 d88_output.asm^
 fd_capture.asm^
 read_report.asm^
 confirm.asm

SET FD_D88_DST=%RELEASE_DIR%\fd2img.com

SET D88_FD_SRC= ^
 value_define.asm^
 d88_fd_define.asm^
 d88_fd_main.asm^
 runtime.asm^
 cli.asm^
 console.asm^
 iocs_fdd.asm^
 d88_common.asm^
 d88_input.asm^
 fd_restore.asm^
 confirm.asm

SET D88_FD_DST=%RELEASE_DIR%\img2fd.com

echo # ------------------------------------------- #
echo # アセンブル (%FD_D88_DST%)
echo # ------------------------------------------- #
echo %FD_D88_SRC% → %FD_D88_DST%

%CMD% -o %FD_D88_DST% %FD_D88_SRC% -x

if %ERRORLEVEL% neq 0 (
  cd %WDIR%
  echo @@ Makeでエラーが発生しました。@@
  exit /b 1
)

echo # ------------------------------------------- #
echo # アセンブル (%D88_FD_DST%)
echo # ------------------------------------------- #
echo %D88_FD_SRC% → %D88_FD_DST%

%CMD% -o %D88_FD_DST% %D88_FD_SRC% -x

if %ERRORLEVEL% neq 0 (
  cd %WDIR%
  echo @@ Makeでエラーが発生しました。@@
  exit /b 1
)

echo @@ Makeが成功しました。@@

rem 引数指定があれば pause
IF NOT "%1"=="nopause" pause

exit /b 0

