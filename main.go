package main

import (
	"flag"
	"net/http/httputil"
	"net/url"
	"fmt"
	"net/http"
	"os/signal"
	"os"
	"context"
	"syscall"
)

var (
	certFile string
	keyFile  string
	upstream string
	addr     string
)

func init() {
	flag.StringVar(&certFile, "cert-file", "", "path to cert file")
	flag.StringVar(&keyFile, "key-file", "", "path to key file")
	flag.StringVar(&upstream, "upstream", "", "upstream address")
	flag.StringVar(&addr, "addr", ":443", "listen address")
}

func _main() error {
	flag.Parse()

	u, err := url.Parse(upstream)
	if err != nil {
		return fmt.Errorf("invalid upstream address: %v", err)
	}

	rp := httputil.NewSingleHostReverseProxy(u)
	srv := http.Server{
		Handler: rp,
		Addr:    addr,
	}

	idleConnsClosed := make(chan struct{})
	go func() {
		sig := make(chan os.Signal, 1)
		signal.Notify(sig, os.Interrupt, syscall.SIGTERM)
		fmt.Println(<-sig)

		// We received an interrupt signal, shut down.
		if err := srv.Shutdown(context.Background()); err != nil {
			// Error from closing listeners, or context timeout:
			fmt.Printf("HTTP server Shutdown: %v", err)
		}
		close(idleConnsClosed)
	}()

	if err := srv.ListenAndServeTLS(certFile, keyFile); err != http.ErrServerClosed {
		// Error starting or closing listener:
		return fmt.Errorf("ListenAndServeTLS: %v", err)
	}

	<-idleConnsClosed

	return nil
}

func main() {
	err := _main()
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}
