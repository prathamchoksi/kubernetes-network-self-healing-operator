FROM golang:1.20 AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o operator-webhook .

FROM gcr.io/distroless/static:nonroot
WORKDIR /
COPY --from=builder /app/operator-webhook .
USER 65532:65532

ENTRYPOINT ["/operator-webhook"]
