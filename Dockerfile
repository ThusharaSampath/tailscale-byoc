FROM golang:1.23.3-alpine3.20

RUN mkdir /app

WORKDIR /app

ENV TSFILE=tailscale_1.78.1_amd64.tgz

# install curl
RUN apk add --no-cache curl

RUN wget https://pkgs.tailscale.com/stable/${TSFILE} && \
  tar xzf ${TSFILE} --strip-components=1 && \
  rm ${TSFILE}

RUN mkdir -p /var/run/tailscale /var/cache/tailscale /var/lib/tailscale /home/choreouser

# Create a new user with UID 10014
RUN addgroup -g 10014 choreo && \
    adduser  --disabled-password --uid 10014 --ingroup choreo choreouser

RUN chown -R 10014:10014 /var/run/tailscale /var/cache/tailscale /var/lib/tailscale /home/choreouser && \
    chmod -R 755 /var/run/tailscale /var/cache/tailscale /var/lib/tailscale

# Download Go modules
COPY go.mod ./
COPY go.sum ./
RUN go mod download

COPY *.go ./

# Build go program
RUN CGO_ENABLED=0 GOOS=linux go build -o /proxy-pass

EXPOSE 1055 8080

WORKDIR /home/choreouser

COPY start.sh .

RUN chmod +x start.sh

USER 10014

CMD ["/home/choreouser/start.sh"]
