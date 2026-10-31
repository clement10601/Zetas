# Zetas 導演伺服器映像：ZeWorld 導演（engine/director）＋ Zetas 遊戲資料。
# 在 repo 根目錄建置（要先 git submodule update --init）：
#   docker build -f deploy/director/Dockerfile -t zetas-director .
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN pip install "jsonschema==4.26.0" "anthropic==2.3.0" \
 && useradd --uid 10001 --create-home --shell /usr/sbin/nologin director \
 && mkdir -p /data && chown 10001:10001 /data

WORKDIR /app
COPY engine/director /app/engine/director
COPY engine/content-pack /app/engine/content-pack
COPY zeworld.json /app/zeworld.json
COPY content /app/content

# 存取碼檔（只有雜湊）從 Secret 掛到 /secrets/codes.json；用量和生成的內容包寫到 /data（PVC）。
ENV ZEWORLD_DIRECTOR_ACCESS_CODES=/secrets/codes.json \
    ZEWORLD_DIRECTOR_USAGE=/data/usage.json

USER 10001
WORKDIR /app/engine
EXPOSE 8765
HEALTHCHECK --interval=30s --timeout=3s CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8765/v1/health', timeout=2).status == 200 else 1)"
ENTRYPOINT ["python", "-m", "director"]
CMD ["serve", "--game", "/app/zeworld.json", "--host", "0.0.0.0", "--port", "8765", "--out", "/data/generated"]
