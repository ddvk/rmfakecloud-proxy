// secure is a super simple TLS termination proxy
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
)

var (
	certFile string
	keyFile  string
	upstream string
	addr     string
	version  bool
)

func init() {
	flag.StringVar(&addr, "addr", ":443", "listen address")
	flag.StringVar(&certFile, "cert", "", "path to cert file")
	flag.StringVar(&keyFile, "key", "", "path to key file")
	flag.BoolVar(&version, "version", false, "print version string and exit")

	flag.Usage = func() {
		fmt.Fprintf(flag.CommandLine.Output(),
			"usage: %s [-addr host:port] -cert certfile -key keyfile [-version] upstream\n",
			filepath.Base(os.Args[0]))
		flag.PrintDefaults()
		fmt.Fprintln(flag.CommandLine.Output(), "  upstream string\n    \tupstream url")
	}
}

func _main() error {
	flag.Parse()

	if version {
		fmt.Fprintln(flag.CommandLine.Output(), Version)
		os.Exit(0)
	}

	if flag.NArg() == 1 {
		upstream = flag.Arg(0)
	} else {
		flag.Usage()
		os.Exit(2)
	}

	u, err := url.Parse(upstream)
	if err != nil {
		return fmt.Errorf("invalid upstream address: %v", err)
	}

	rp := httputil.NewSingleHostReverseProxy(u)
	srv := http.Server{
		Handler: rp,
		Addr:    addr,
	}

	done := make(chan struct{})
	go func() {
		sig := make(chan os.Signal, 1)
		signal.Notify(sig, os.Interrupt, syscall.SIGTERM)
		fmt.Println(<-sig)

		if err := srv.Shutdown(context.Background()); err != nil {
			fmt.Printf("Shutdown: %v", err)
		}
		close(done)
	}()

	log.Printf("cert-file=%s key-file=%s listen-addr=%s upstream-url=%s", certFile, keyFile, srv.Addr, u.String())
	if err := srv.ListenAndServeTLS(certFile, keyFile); err != http.ErrServerClosed {
		return fmt.Errorf("ListenAndServeTLS: %v", err)
	}

	<-done
	return nil
}

func main() {
	err := _main()
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}
