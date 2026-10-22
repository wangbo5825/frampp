@echo off
set "FRAMPP_HOME=%~dp0.."
set "PHPRC=%FRAMPP_HOME%\etc\php.ini"
if exist "%FRAMPP_HOME%\modules\frankenphp\php.exe" (
  "%FRAMPP_HOME%\modules\frankenphp\php.exe" -d memory_limit=1G "%FRAMPP_HOME%\modules\composer\composer.phar" %*
) else (
  "%FRAMPP_HOME%\modules\frankenphp\frankenphp.exe" php-cli -d memory_limit=1G "%FRAMPP_HOME%\modules\composer\composer.phar" %*
)
