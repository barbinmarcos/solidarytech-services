FROM python:3.11-slim

# ============================================================
# PYTHON
# ============================================================

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# ============================================================
# PROMETHEUS - MULTIPROCESS MODE
# Necessário porque o Gunicorn executa múltiplos workers.
# ============================================================

ENV PROMETHEUS_MULTIPROC_DIR=/tmp/prometheus

# ============================================================
# APPLICATION
# ============================================================

WORKDIR /app

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# ============================================================
# NON-ROOT USER + PROMETHEUS DIRECTORY
# ============================================================

RUN useradd \
    --create-home \
    --uid 10001 \
    appuser \
    && mkdir -p /tmp/prometheus \
    && chown -R appuser:appuser /tmp/prometheus

USER appuser

# ============================================================
# SERVICE
# ============================================================

EXPOSE 8083

# Limpa os arquivos multiprocess antigos antes de iniciar
# o Gunicorn. O "exec" garante que o Gunicorn seja o processo
# principal do container e receba corretamente os sinais.
CMD ["sh", "-c", "rm -rf /tmp/prometheus/* && exec gunicorn --bind 0.0.0.0:8083 --workers 2 app:app"]
