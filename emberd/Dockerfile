FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY *.py schema.json ./

EXPOSE 8765
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8765/health',timeout=4).status==200 else 1)"
# options.json + AuthKey.p8 are mounted at /data (see compose.yaml), never baked in.
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8765"]
