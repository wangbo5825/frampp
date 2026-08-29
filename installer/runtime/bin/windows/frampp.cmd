@echo off
rem FRAMPP CLI 包装器（Windows）
set "FRAMPP_HOME=%~dp0.."
set "PHPRC=%FRAMPP_HOME%\etc\php.ini"
"%FRAMPP_HOME%\modules\frankenphp\frankenphp.exe" php-cli "%FRAMPP_HOME%\modules\control-panel\bin\frampp" %*
