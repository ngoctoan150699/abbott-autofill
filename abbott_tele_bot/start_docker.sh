#!/bin/bash
cd "$(dirname "$0")"

echo "======================================================="
echo "   KHOI DONG ABBOTT FILL TELEGRAM BOT (DOCKER COMPOSE)"
echo "======================================================="
echo ""
docker compose up -d --build
if [ $? -ne 0 ]; then
    echo "[!] Co loi xay ra khi khoi dong Docker."
    exit 1
fi

echo ""
echo "[+] Bot da duoc khoi dong thanh cong trong Docker!"
echo "[+] Xem logs cua Bot bang cach chay: docker compose logs -f"
echo "[+] Dung bot bang cach chay: docker compose down"
echo ""
