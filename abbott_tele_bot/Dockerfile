# ==============================================================================
# Dockerfile cho Abbott Telegram Bot Automation
# Base Image: Microsoft Playwright Jammy (đầy đủ dependencies cho Chromium Headless)
# ==============================================================================
FROM mcr.microsoft.com/playwright/python:v1.49.0-jammy

# Thiết lập biến môi trường
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    TZ=Asia/Ho_Chi_Minh \
    DEBIAN_FRONTEND=noninteractive

WORKDIR /app

# Cài đặt tzdata, ca-certificates, libzbar0 (cho pyzbar quét mã QR), và font tiếng Việt
RUN apt-get update && apt-get install -y --no-install-recommends \
    tzdata \
    ca-certificates \
    libzbar0 \
    fonts-liberation \
    fonts-noto-color-emoji \
    fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

# Cài đặt Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Đảm bảo Chromium browser được cài đặt sẵn
RUN playwright install chromium

# Copy toàn bộ mã nguồn vào container
COPY . .

# Tạo các thư mục data, screenshots, downloads
RUN mkdir -p /app/data /app/screenshots /app/downloads

# Khởi động Bot Telegram
CMD ["python", "-u", "telegram_bot.py"]
