@echo off
setlocal
cd /d "%~dp0"
title Windows Utilities PT-PT - Diagnostico
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0INICIAR-DIAGNOSTICO.ps1"
set "RESULTADO=%ERRORLEVEL%"
if not "%RESULTADO%"=="0" (
  echo.
  echo O arranque falhou. Consulta ERRO-ARRANQUE.txt nesta pasta.
  echo.
  pause
)
exit /b %RESULTADO%
