package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"time"

	"golang.org/x/net/proxy"
	"gopkg.in/yaml.v3"
)

const (
	proxyAddr         = "localhost:1055"
	connectionTimeout = 5 * time.Minute  // Timeout for idle connections
	dialTimeout       = 30 * time.Second // Timeout for establishing connections
	maxRetries        = 3                // Maximum retry attempts for proxy connection
	retryBaseDelay    = 1 * time.Second  // Base delay for exponential backoff
)

// Config struct to hold the YAML configuration
type Config struct {
	PortMappings map[int]string `yaml:"portMappings"`
}

func handleConnection(conn net.Conn, dialer proxy.Dialer, destinationAddr string) {
	defer conn.Close()

	// Enable TCP keep-alive to detect dead connections during Tailscale mode transitions
	if tcpConn, ok := conn.(*net.TCPConn); ok {
		if err := tcpConn.SetKeepAlive(true); err != nil {
			log.Printf("Failed to enable TCP keep-alive: %v", err)
		} else if err := tcpConn.SetKeepAlivePeriod(30 * time.Second); err != nil {
			log.Printf("Failed to set TCP keep-alive period: %v", err)
		}
	}

	// Dial the destination address through the SOCKS5 proxy with retry logic
	var proxyConn net.Conn
	var err error

	for attempt := 0; attempt < maxRetries; attempt++ {
		proxyConn, err = dialer.Dial("tcp", destinationAddr)
		if err == nil {
			break
		}

		// Log retry attempts
		if attempt < maxRetries-1 {
			retryDelay := retryBaseDelay * time.Duration(1<<uint(attempt)) // Exponential backoff
			log.Printf("Failed to connect to destination %s through proxy (attempt %d/%d): %v. Retrying in %v...",
				destinationAddr, attempt+1, maxRetries, err, retryDelay)
			time.Sleep(retryDelay)
		} else {
			log.Printf("Failed to connect to destination %s through proxy after %d attempts: %v",
				destinationAddr, maxRetries, err)
		}
	}

	if err != nil {
		return
	}
	defer proxyConn.Close()

	// Enable TCP keep-alive on proxy connection as well
	if tcpProxyConn, ok := proxyConn.(*net.TCPConn); ok {
		if err := tcpProxyConn.SetKeepAlive(true); err != nil {
			log.Printf("Failed to enable TCP keep-alive on proxy connection: %v", err)
		} else if err := tcpProxyConn.SetKeepAlivePeriod(30 * time.Second); err != nil {
			log.Printf("Failed to set TCP keep-alive period on proxy connection: %v", err)
		}
	}

	// Don't set read deadlines - let connections close naturally when both sides finish
	// TCP keep-alive will detect truly dead connections over time

	// Create context for coordinated shutdown of bidirectional copy
	_, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Channel to collect errors from both goroutines
	errChan := make(chan error, 2)

	// Copy from client to proxy (upstream)
	go func() {
		_, err := io.Copy(proxyConn, conn)
		if err != nil && err != io.EOF {
			log.Printf("[%s] Upstream copy error (client->proxy): %v", destinationAddr, err)
		}
		errChan <- err

		// Close write side of client connection to signal we're done reading from client
		if tcpConn, ok := conn.(*net.TCPConn); ok {
			tcpConn.CloseRead()
		}

		cancel() // Signal the other goroutine to stop
	}()

	// Copy from proxy to client (downstream)
	go func() {
		_, err := io.Copy(conn, proxyConn)
		if err != nil && err != io.EOF {
			log.Printf("[%s] Downstream copy error (proxy->client): %v", destinationAddr, err)
		}
		errChan <- err

		// Close the write side to signal EOF to the client
		if tcpConn, ok := conn.(*net.TCPConn); ok {
			tcpConn.CloseWrite()
		}

		// Close proxyConn to interrupt upstream io.Copy
		proxyConn.Close()

		cancel() // Signal the other goroutine to stop
	}()

	// Wait for both goroutines to complete
	for i := 0; i < 2; i++ {
		<-errChan
	}

	// Ensure both connections are properly closed
	log.Printf("Connection closed for destination %s", destinationAddr)
}

func main() {

	configPath := flag.String("config", "config.yaml", "path to the config file")
	flag.Parse()

	file, err := os.Open(*configPath)
	if err != nil {
		log.Fatalf("error opening config file: %v", err)
	}

	defer file.Close()

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

	select {}
}
