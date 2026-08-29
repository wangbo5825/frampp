@echo off
rem FRAMPP pip（Windows）
set "FRAMPP_HOME=%~dp0.."
"%FRAMPP_HOME%\modules\python\python.exe" -m pip %*
