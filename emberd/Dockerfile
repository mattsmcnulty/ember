FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY *.py schema.json ./

EXPOSE 8765
# options.json + AuthKey.p8 are mounted at /data (see compose.yaml), never baked in.
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8765"]
