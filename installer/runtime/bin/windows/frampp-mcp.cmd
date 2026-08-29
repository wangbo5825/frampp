@echo off
set "FRAMPP_HOME=%~dp0.."
set "PHPRC=%FRAMPP_HOME%\etc\php.ini"
"%FRAMPP_HOME%\modules\frankenphp\frankenphp.exe" php-cli "%FRAMPP_HOME%\modules\agent\bin\frampp-mcp" %*
