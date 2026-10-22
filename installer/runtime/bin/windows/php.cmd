@echo off
set "FRAMPP_HOME=%~dp0.."
set "PHPRC=%FRAMPP_HOME%\etc\php.ini"
if exist "%FRAMPP_HOME%\modules\frankenphp\php.exe" (
  "%FRAMPP_HOME%\modules\frankenphp\php.exe" %*
) else (
  "%FRAMPP_HOME%\modules\frankenphp\frankenphp.exe" php-cli %*
)
