import os
import sys
import uuid
import time
import logging

import boto3
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

from opentelemetry.exporter.otlp.proto.http.trace_exporter import (
    OTLPSpanExporter,
)

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
    "volunteer_http_requests_total",
    "Total de requisições HTTP recebidas pelo volunteer-service",
    ["method", "path", "status"],
)

HTTP_REQUEST_DURATION = Histogram(
    "volunteer_http_request_duration_seconds",
    "Duração das requisições HTTP do volunteer-service",
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
            "service.name": "volunteer-service",
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
# DYNAMODB
# ============================================================

AWS_REGION = os.getenv(
    "AWS_REGION",
    "us-east-1",
)

DYNAMODB_TABLE = os.getenv(
    "AWS_DYNAMODB_TABLE"
)

DYNAMODB_ENDPOINT = os.getenv(
    "AWS_DYNAMODB_ENDPOINT"
)

if not DYNAMODB_TABLE:
    log.critical(
        "Erro: AWS_DYNAMODB_TABLE não definida."
    )
    sys.exit(1)

try:
    dynamodb = boto3.resource(
        "dynamodb",
        region_name=AWS_REGION,
        endpoint_url=(
            DYNAMODB_ENDPOINT
            if DYNAMODB_ENDPOINT
            else None
        ),
    )

    table = dynamodb.Table(
        DYNAMODB_TABLE
    )

    log.info(
        "Conectado à tabela DynamoDB: %s",
        DYNAMODB_TABLE,
    )

except Exception as e:
    log.critical(
        "Falha ao conectar no DynamoDB: %s",
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
            "service": "volunteer-service",
        }
    )


# ============================================================
# REGISTER VOLUNTEER
# ============================================================

@app.route(
    "/volunteers",
    methods=["POST"],
)
def register_volunteer():

    data = request.get_json()

    required_fields = (
        "name",
        "email",
        "ngo_id",
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

    volunteer_id = str(
        uuid.uuid4()
    )

    item = {
        "volunteer_id": volunteer_id,
        "name": data["name"],
        "email": data["email"],
        "ngo_id": int(
            data["ngo_id"]
        ),
        "registered_at": str(
            int(time.time())
        ),
    }

    try:
        table.put_item(
            Item=item
        )

        return jsonify(
            item
        ), 201

    except Exception as e:
        log.error(
            "Erro ao salvar voluntário no DynamoDB: %s",
            e,
        )

        return jsonify(
            {
                "error": "Erro interno ao processar dados"
            }
        ), 500


# ============================================================
# GET VOLUNTEERS BY NGO
# ============================================================

@app.route(
    "/volunteers/<int:ngo_id>",
    methods=["GET"],
)
def get_volunteers_by_ngo(ngo_id):

    try:
        response = table.scan(
            FilterExpression=(
                boto3.dynamodb.conditions.Attr(
                    "ngo_id"
                ).eq(
                    ngo_id
                )
            )
        )

        return jsonify(
            response.get(
                "Items",
                [],
            )
        ), 200

    except Exception as e:
        log.error(
            "Erro ao buscar dados no DynamoDB: %s",
            e,
        )

        return jsonify(
            {
                "error": "Erro interno"
            }
        ), 500


# ============================================================
# MAIN
# ============================================================

if __name__ == "__main__":

    port = int(
        os.getenv(
            "PORT",
            8083,
        )
    )

    log.info(
        "volunteer-service rodando na porta %s",
        port,
    )

    app.run(
        host="0.0.0.0",
        port=port,
    )
