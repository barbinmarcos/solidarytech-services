package main

import (
	"database/sql"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/sqs"
	_ "github.com/jackc/pgx/v4/stdlib"
	"github.com/joho/godotenv"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

type Donation struct {
	ID        int       `json:"id"`
	NgoID     int       `json:"ngo_id"`
	Amount    float64   `json:"amount"`
	DonorName string    `json:"donor_name"`
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"created_at"`
}

type App struct {
	DB          *sql.DB
	SqsSvc      *sqs.SQS
	SqsQueueURL string
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

var (
	httpRequestsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "donation_http_requests_total",
			Help: "Total de requisições HTTP recebidas pelo donation-service",
		},
		[]string{"method", "path", "status"},
	)

	httpRequestDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "donation_http_request_duration_seconds",
			Help:    "Duração das requisições HTTP do donation-service",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"method", "path"},
	)
)

func main() {
	_ = godotenv.Load()

	prometheus.MustRegister(httpRequestsTotal)
	prometheus.MustRegister(httpRequestDuration)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8082"
	}

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal("DATABASE_URL é obrigatória")
	}

	db, err := sql.Open("pgx", dbURL)
	if err != nil {
		log.Fatalf("Erro ao abrir conexão com o banco: %v", err)
	}
	defer db.Close()

	if err := db.Ping(); err != nil {
		log.Fatalf("Erro ao conectar ao banco: %v", err)
	}

	log.Println("Conectado ao PostgreSQL (donation-service).")

	var sqsSvc *sqs.SQS

	queueURL := os.Getenv("AWS_SQS_URL")
	region := os.Getenv("AWS_REGION")

	if queueURL != "" && region != "" {
		sess, err := session.NewSession(
			&aws.Config{
				Region: aws.String(region),
			},
		)

		if err != nil {
			log.Printf("Erro ao criar sessão AWS: %v", err)
		} else {
			sqsSvc = sqs.New(sess)
			log.Println("Integração com AWS SQS ativada.")
		}
	}

	app := &App{
		DB:          db,
		SqsSvc:      sqsSvc,
		SqsQueueURL: queueURL,
	}

	mux := http.NewServeMux()

	mux.HandleFunc("/health", app.HealthHandler)
	mux.HandleFunc("/donations", app.DonationHandler)
	mux.Handle("/metrics", promhttp.Handler())

	handler := metricsMiddleware(mux)

	server := &http.Server{
		Addr:              ":" + port,
		Handler:           handler,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	log.Printf("donation-service rodando na porta %s", port)

	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("Erro ao iniciar servidor HTTP: %v", err)
	}
}

func metricsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/metrics" {
			next.ServeHTTP(w, r)
			return
		}

		start := time.Now()

		recorder := &statusRecorder{
			ResponseWriter: w,
			status:         http.StatusOK,
		}

		next.ServeHTTP(recorder, r)

		httpRequestsTotal.WithLabelValues(
			r.Method,
			r.URL.Path,
			http.StatusText(recorder.status),
		).Inc()

		httpRequestDuration.WithLabelValues(
			r.Method,
			r.URL.Path,
		).Observe(time.Since(start).Seconds())
	})
}

func (a *App) HealthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)

	if _, err := w.Write(
		[]byte(`{"status":"ok","service":"donation-service"}`),
	); err != nil {
		log.Printf("Erro ao escrever resposta do health check: %v", err)
	}
}

func (a *App) DonationHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	// Simulação controlada de latência para testes de observabilidade.
	//
	// SIMULATE_LATENCY_MS=800
	// adiciona aproximadamente 800 ms ao endpoint /donations.
	//
	// SIMULATE_LATENCY_MS=0
	// mantém o comportamento normal.
	if delay := os.Getenv("SIMULATE_LATENCY_MS"); delay != "" {
		ms, err := strconv.Atoi(delay)

		if err != nil {
			log.Printf(
				"Valor inválido para SIMULATE_LATENCY_MS: %s",
				delay,
			)
		} else if ms > 0 {
			time.Sleep(time.Duration(ms) * time.Millisecond)
		}
	}

	switch r.Method {
	case http.MethodPost:
		a.createDonation(w, r)

	case http.MethodGet:
		a.listDonations(w)

	default:
		http.Error(
			w,
			`{"error":"Método não permitido"}`,
			http.StatusMethodNotAllowed,
		)
	}
}

func (a *App) createDonation(w http.ResponseWriter, r *http.Request) {
	var d Donation

	if err := json.NewDecoder(r.Body).Decode(&d); err != nil {
		http.Error(
			w,
			`{"error":"Payload inválido"}`,
			http.StatusBadRequest,
		)
		return
	}

	d.Status = "APPROVED"

	err := a.DB.QueryRow(
		`
		INSERT INTO donations
			(ngo_id, amount, donor_name, status)
		VALUES
			($1, $2, $3, $4)
		RETURNING id, created_at
		`,
		d.NgoID,
		d.Amount,
		d.DonorName,
		d.Status,
	).Scan(
		&d.ID,
		&d.CreatedAt,
	)

	if err != nil {
		log.Printf("Erro ao salvar doação: %v", err)

		http.Error(
			w,
			`{"error":"Erro interno"}`,
			http.StatusInternalServerError,
		)
		return
	}

	if a.SqsSvc != nil {
		go a.sendNotificationEvent(d)
	}

	w.WriteHeader(http.StatusCreated)

	if err := json.NewEncoder(w).Encode(d); err != nil {
		log.Printf("Erro ao serializar resposta da doação: %v", err)
	}
}

func (a *App) listDonations(w http.ResponseWriter) {
	rows, err := a.DB.Query(
		`
		SELECT
			id,
			ngo_id,
			amount,
			donor_name,
			status,
			created_at
		FROM donations
		ORDER BY id DESC
		`,
	)

	if err != nil {
		log.Printf("Erro ao consultar doações: %v", err)

		http.Error(
			w,
			`{"error":"Erro interno"}`,
			http.StatusInternalServerError,
		)
		return
	}

	defer rows.Close()

	donations := []Donation{}

	for rows.Next() {
		var d Donation

		err := rows.Scan(
			&d.ID,
			&d.NgoID,
			&d.Amount,
			&d.DonorName,
			&d.Status,
			&d.CreatedAt,
		)

		if err != nil {
			log.Printf("Erro ao ler doação do banco: %v", err)

			http.Error(
				w,
				`{"error":"Erro interno"}`,
				http.StatusInternalServerError,
			)
			return
		}

		donations = append(donations, d)
	}

	if err := rows.Err(); err != nil {
		log.Printf("Erro ao iterar resultado das doações: %v", err)

		http.Error(
			w,
			`{"error":"Erro interno"}`,
			http.StatusInternalServerError,
		)
		return
	}

	if err := json.NewEncoder(w).Encode(donations); err != nil {
		log.Printf("Erro ao serializar lista de doações: %v", err)
	}
}

func (a *App) sendNotificationEvent(d Donation) {
	if a.SqsSvc == nil || a.SqsQueueURL == "" {
		log.Printf("SQS não configurado; evento não enviado")
		return
	}

	body, err := json.Marshal(d)
	if err != nil {
		log.Printf("Erro ao serializar evento para SQS: %v", err)
		return
	}

	result, err := a.SqsSvc.SendMessage(
		&sqs.SendMessageInput{
			QueueUrl:    aws.String(a.SqsQueueURL),
			MessageBody: aws.String(string(body)),
		},
	)

	if err != nil {
		log.Printf("Erro ao enviar evento para SQS: %v", err)
		return
	}

	log.Printf(
		"Evento enviado ao SQS com sucesso. MessageId=%s",
		aws.StringValue(result.MessageId),
	)
}
