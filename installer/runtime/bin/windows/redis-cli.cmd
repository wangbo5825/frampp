@echo off
set "FRAMPP_HOME=%~dp0.."
"%FRAMPP_HOME%\modules\redis\redis-cli.exe" %*
