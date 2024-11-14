FROM golang:1.23.3-alpine3.20 as tailscale

RUN mkdir /app

WORKDIR /app

ARG TAILSCALE_VERSION
RUN wget https://pkgs.tailscale.com/stable/tailscale_${TAILSCALE_VERSION}_amd64.tgz && \
  tar xzf tailscale_${TAILSCALE_VERSION}_amd64.tgz --strip-components=1 && \
  rm tailscale_${TAILSCALE_VERSION}_amd64.tgz

# Download Go modules
COPY go.mod ./
COPY go.sum ./
RUN go mod download

COPY *.go ./

# Build go program
RUN CGO_ENABLED=0 GOOS=linux go build -o /proxy-pass

from alpine:3.20
COPY --from=tailscale /proxy-pass /proxy-pass
COPY --from=tailscale /app/tailscaled /tailscaled
COPY --from=tailscale /app/tailscale /tailscale
RUN mkdir -p /var/run/tailscale /var/cache/tailscale /var/lib/tailscale

EXPOSE 1055 8080

COPY start.sh .

RUN chmod +x start.sh

ENTRYPOINT ["./start.sh"]