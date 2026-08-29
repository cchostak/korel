FROM golang:1.22-alpine AS builder

WORKDIR /build

RUN apk add --no-cache git

COPY go.mod go.sum ./
RUN go mod download

COPY main.go .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /app/business-service main.go

FROM alpine:3.20

WORKDIR /app
RUN apk add --no-cache ca-certificates curl

COPY --from=builder /app/business-service /app/business-service

EXPOSE 8080

CMD ["/app/business-service"]
