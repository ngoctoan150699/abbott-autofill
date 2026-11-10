@echo off
chcp 65001 > nul
title Abbott Fill Bot - Stop Docker
cd /d "%~dp0"

echo DANG DUNG CONTAINER ABBOTT BOT...
docker compose down
echo [+] Da dung thanh cong!
pause
