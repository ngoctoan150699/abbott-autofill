@echo off
chcp 65001 > nul
title Abbott Fill Bot - Docker Runner
cd /d "%~dp0"

echo =======================================================
echo   KHOI DONG ABBOTT FILL TELEGRAM BOT (DOCKER COMPOSE)
echo =======================================================
echo.
docker compose up -d --build
if %errorlevel% neq 0 (
    echo [!] Co loi xay ra khi khoi dong Docker.
    pause
    exit /b %errorlevel%
)

echo.
echo [+] Bot da duoc khoi dong thanh cong trong Docker!
echo [+] Xem logs cua Bot bang cach chay: docker compose logs -f
echo [+] Dung bot bang cach chay: docker compose down
echo.
pause
