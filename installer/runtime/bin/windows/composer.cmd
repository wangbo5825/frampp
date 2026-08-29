@echo off
rem FRAMPP Composer（Windows）
set "FRAMPP_HOME=%~dp0.."
set "PHPRC=%FRAMPP_HOME%\etc\php.ini"
"%FRAMPP_HOME%\modules\frankenphp\frankenphp.exe" php-cli -d memory_limit=1G "%FRAMPP_HOME%\modules\composer\composer.phar" %*
