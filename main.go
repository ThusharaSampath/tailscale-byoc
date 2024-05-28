package main

import (
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"

	"golang.org/x/net/proxy"
	"gopkg.in/yaml.v3"
)

const (
	proxyAddr     = "localhost:1055"
	healthPort    = "8000" // Port for health checks
	healthPath    = "/healthz"
	readinessPath = "/readiness"
)

// Config struct to hold the YAML configuration
type Config struct {
	PortMappings map[int]string `yaml:"portMappings"`
}

func healthzHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	_, err := fmt.Fprintln(w, "ok")
	if err != nil {
		log.Printf("Error writing healthz response: %v", err)
		return
	}
}

func readinessHandler(w http.ResponseWriter, r *http.Request) {
	// Here you might want to add some checks to see if your application is ready
	// For simplicity, we return OK
	w.WriteHeader(http.StatusOK)
	_, err := fmt.Fprintln(w, "ready")
	if err != nil {
		log.Printf("Error writing readiness response: %v", err)
		return
	}
}

func handleConnection(conn net.Conn, dialer proxy.Dialer, destinationAddr string) {
	defer conn.Close()

	// Dial the destination address through the SOCKS5 proxy
	proxyConn, err := dialer.Dial("tcp", destinationAddr)
	if err != nil {
		log.Printf("Failed to connect to destination %s through proxy: %v", destinationAddr, err)
		return
	}
	defer proxyConn.Close()

	go func() {
		if _, err := io.Copy(proxyConn, conn); err != nil {
			log.Printf("Failed to copy data to proxy connection: %v", err)
		}
	}()
	if _, err := io.Copy(conn, proxyConn); err != nil {
		log.Printf("Failed to copy data to client connection: %v", err)
	}
}

func main() {
	// Read the YAML file
	file, err := os.Open("Config.yaml")
	if err != nil {
		log.Fatalf("error opening config file: %v", err)
	}

	defer file.Close()

	// Read the file content
	fileInfo, err := file.Stat()
	if err != nil {
		log.Fatalf("error: %v", err)
	}

	fileSize := fileInfo.Size()
	fileContent := make([]byte, fileSize)

	_, err = file.Read(fileContent)
	if err != nil {
		log.Fatalf("error: %v", err)
	}

	// Unmarshal the YAML into the Config struct
	var config Config
	err = yaml.Unmarshal(fileContent, &config)
	if err != nil {
		log.Fatalf("error: %v", err)
	}

	// Create a proxy dialer
	dialer, err := proxy.SOCKS5("tcp", proxyAddr, nil, proxy.Direct)
	if err != nil {
		log.Fatalf("Failed to connect to SOCKS5 proxy: %v", err)
	}

	for port, destinationAddr := range config.PortMappings {
		listenAddr := fmt.Sprintf("0.0.0.0:%d", port)
		go func(listenAddr, destinationAddr string) {
			listener, err := net.Listen("tcp", listenAddr)
			if err != nil {
				log.Fatalf("Failed to listen on %s: %v", listenAddr, err)
			}
			defer listener.Close()
			log.Printf("Listening on %s and forwarding to %s via proxy %s", listenAddr, destinationAddr, proxyAddr)

			for {
				conn, err := listener.Accept()
				if err != nil {
					log.Printf("Failed to accept connection: %v", err)
					continue
				}
				go handleConnection(conn, dialer, destinationAddr)
			}
		}(listenAddr, destinationAddr)
	}

	// Start HTTP server for health checks
	http.HandleFunc(healthPath, healthzHandler)
	http.HandleFunc(readinessPath, readinessHandler)
	go func() {
		log.Printf("Starting health check server on port %s", healthPort)
		if err := http.ListenAndServe(":"+healthPort, nil); err != nil {
			log.Fatalf("Failed to start health check server: %v", err)
		}
	}()

	select {}
}
