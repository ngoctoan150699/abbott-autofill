@echo off
chcp 65001 > nul
title Abbott Fill Bot - Local Runner
cd /d "%~dp0"

echo Dang kiem tra thu vien Python...
python -m pip install -r requirements.txt
python -m playwright install chromium

echo.
echo Khoi dong Abbott Telegram Bot tren may cuc bo...
python telegram_bot.py
pause
