import os
import sys
import time
import logging

import psycopg2
from psycopg2.extras import RealDictCursor
from psycopg2.pool import SimpleConnectionPool

from flask import Flask, request, jsonify, Response
from dotenv import load_dotenv

from prometheus_client import (
    Counter,
    Histogram,
    generate_latest,
    CONTENT_TYPE_LATEST,
)

from opentelemetry import trace
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.flask import FlaskInstrumentor


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
)

log = logging.getLogger(__name__)

load_dotenv()

app = Flask(__name__)


# ============================================================
# PROMETHEUS
# ============================================================

HTTP_REQUESTS_TOTAL = Counter(
    "ngo_http_requests_total",
    "Total de requisições HTTP recebidas pelo ngo-service",
    ["method", "path", "status"],
)

HTTP_REQUEST_DURATION = Histogram(
    "ngo_http_request_duration_seconds",
    "Duração das requisições HTTP do ngo-service",
    ["method", "path"],
)


@app.before_request
def start_request_timer():
    request._start_time = time.time()


@app.after_request
def record_request_metrics(response):
    if request.path == "/metrics":
        return response

    duration = time.time() - getattr(
        request,
        "_start_time",
        time.time(),
    )

    HTTP_REQUESTS_TOTAL.labels(
        method=request.method,
        path=request.path,
        status=str(response.status_code),
    ).inc()

    HTTP_REQUEST_DURATION.labels(
        method=request.method,
        path=request.path,
    ).observe(duration)

    return response


@app.route("/metrics")
def metrics():
    return Response(
        generate_latest(),
        mimetype=CONTENT_TYPE_LATEST,
    )


# ============================================================
# OPENTELEMETRY
# ============================================================

def init_tracing():
    endpoint = os.getenv(
        "OTEL_EXPORTER_OTLP_ENDPOINT",
        "https://otlp.nr-data.net:4318/v1/traces",
    )

    resource = Resource.create(
        {
            "service.name": "ngo-service",
            "deployment.environment": "production",
        }
    )

    provider = TracerProvider(
        resource=resource,
    )

    exporter = OTLPSpanExporter(
        endpoint=endpoint,
    )

    provider.add_span_processor(
        BatchSpanProcessor(exporter)
    )

    trace.set_tracer_provider(provider)

    FlaskInstrumentor().instrument_app(app)

    log.info(
        "OpenTelemetry inicializado. OTLP endpoint=%s",
        endpoint,
    )


init_tracing()


# ============================================================
# DATABASE
# ============================================================

DATABASE_URL = os.getenv("DATABASE_URL")

if not DATABASE_URL:
    log.critical(
        "Erro: DATABASE_URL não definida."
    )
    sys.exit(1)

try:
    pool = SimpleConnectionPool(
        1,
        10,
        dsn=DATABASE_URL,
    )

    log.info(
        "Pool de conexões com o PostgreSQL "
        "(ngo-service) inicializado."
    )

except Exception as e:
    log.critical(
        "Erro ao conectar ao PostgreSQL: %s",
        e,
    )

    sys.exit(1)


# ============================================================
# HEALTH
# ============================================================

@app.route("/health")
def health():
    return jsonify(
        {
            "status": "ok",
            "service": "ngo-service",
        }
    )


# ============================================================
# CREATE NGO
# ============================================================

@app.route("/ngos", methods=["POST"])
def create_ngo():

    data = request.get_json()

    required_fields = (
        "name",
        "email",
        "cause",
        "city",
    )

    if not data or not all(
        key in data
        for key in required_fields
    ):
        return jsonify(
            {
                "error": "Campos obrigatórios ausentes"
            }
        ), 400

    conn = pool.getconn()

    try:
        with conn.cursor(
            cursor_factory=RealDictCursor
        ) as cur:

            cur.execute(
                """
                INSERT INTO ngos
                    (name, email, cause, city)
                VALUES
                    (%s, %s, %s, %s)
                RETURNING *
                """,
                (
                    data["name"],
                    data["email"],
                    data["cause"],
                    data["city"],
                ),
            )

            new_ngo = cur.fetchone()

            conn.commit()

            return jsonify(
                new_ngo
            ), 201

    except psycopg2.IntegrityError:

        conn.rollback()

        return jsonify(
            {
                "error": "E-mail já cadastrado"
            }
        ), 409

    except Exception as e:

        conn.rollback()

        log.error(
            "Erro ao criar ONG: %s",
            e,
        )

        return jsonify(
            {
                "error": "Erro interno"
            }
        ), 500

    finally:

        pool.putconn(conn)


# ============================================================
# LIST NGOS
# ============================================================

@app.route("/ngos", methods=["GET"])
def get_ngos():

    conn = pool.getconn()

    try:

        with conn.cursor(
            cursor_factory=RealDictCursor
        ) as cur:

            cur.execute(
                """
                SELECT *
                FROM ngos
                ORDER BY id DESC
                """
            )

            return jsonify(
                cur.fetchall()
            ), 200

    except Exception as e:

        log.error(
            "Erro ao buscar ONGs: %s",
            e,
        )

        return jsonify(
            {
                "error": "Erro interno"
            }
        ), 500

    finally:

        pool.putconn(conn)


# ============================================================
# MAIN
# ============================================================

if __name__ == "__main__":

    port = int(
        os.getenv(
            "PORT",
            8081,
        )
    )

    log.info(
        "ngo-service rodando na porta %s",
        port,
    )

    app.run(
        host="0.0.0.0",
        port=port,
    )
