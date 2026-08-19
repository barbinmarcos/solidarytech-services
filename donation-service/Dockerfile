FROM golang:1.21-alpine AS builder

WORKDIR /app

COPY go.mod go.sum ./

RUN go mod download

COPY . .

RUN CGO_ENABLED=0 \
    GOOS=linux \
    go build \
    -ldflags="-s -w" \
    -o donation-service .

FROM alpine:3.20

RUN addgroup -S appgroup && \
    adduser -S appuser -G appgroup

WORKDIR /app

COPY --from=builder \
    /app/donation-service \
    /app/donation-service

USER appuser

EXPOSE 8082

ENTRYPOINT ["/app/donation-service"]
