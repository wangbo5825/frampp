@echo off
rem FRAMPP 环境变量（Windows，当前控制台生效）
set "FRAMPP_HOME=%~dp0.."
set "PATH=%FRAMPP_HOME%\bin;%FRAMPP_HOME%\modules\python;%FRAMPP_HOME%\modules\mariadb\bin;%FRAMPP_HOME%\modules\redis;%PATH%"
set "PHPRC=%FRAMPP_HOME%\etc\php.ini"
