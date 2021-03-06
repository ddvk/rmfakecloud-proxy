//go:generate go run generate/versioninfo.go

// secure is a super simple TLS termination proxy
package main

import (
	"context"
	"flag"
	"fmt"
	"gopkg.in/yaml.v3"
	"io/ioutil"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
)

type Config struct {
	CertFile string `yaml:"certfile"`
	KeyFile  string `yaml:"keyfile"`
	Upstream string `yaml:"upstream"`
	Addr     string `yaml:"addr"`
}

var (
	version    bool
	configFile string
)

func getConfig() (config *Config, err error) {
	cfg := Config{}
	flag.StringVar(&configFile, "c", "", "config file")
	flag.StringVar(&cfg.Addr, "addr", ":443", "listen address")
	flag.StringVar(&cfg.CertFile, "cert", "", "path to cert file")
	flag.StringVar(&cfg.KeyFile, "key", "", "path to key file")
	flag.BoolVar(&version, "version", false, "print version string and exit")

	flag.Usage = func() {
		fmt.Fprintf(flag.CommandLine.Output(),
			"usage: %s -c [config.yml] [-addr host:port] -cert certfile -key keyfile [-version] upstream\n",
			filepath.Base(os.Args[0]))
		flag.PrintDefaults()
		fmt.Fprintln(flag.CommandLine.Output(), "  upstream string\n    \tupstream url")
	}
	flag.Parse()

	if version {
		fmt.Fprintln(flag.CommandLine.Output(), Version)
		os.Exit(0)
	}

	if configFile != "" {
		var data []byte
		data, err = ioutil.ReadFile(configFile)

		if err != nil {
			return
		}
		err = yaml.Unmarshal(data, &cfg)
		if err != nil {
			return nil, fmt.Errorf("cant parse config, %v", err)
		}
		return &cfg, nil
	}

	if flag.NArg() == 1 {
		cfg.Upstream = flag.Arg(0)
	} else {
		flag.Usage()
		os.Exit(2)
	}

	return &cfg, nil
}

func _main() error {
	cfg, err := getConfig()
	if err != nil {
		return err
	}

	u, err := url.Parse(cfg.Upstream)
	if err != nil {
		return fmt.Errorf("invalid upstream address: %v", err)
	}

	rp := httputil.NewSingleHostReverseProxy(u)
	srv := http.Server{
		Handler: rp,
		Addr:    cfg.Addr,
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

	log.Printf("cert-file=%s key-file=%s listen-addr=%s upstream-url=%s", cfg.CertFile, cfg.KeyFile, srv.Addr, u.String())
	if err := srv.ListenAndServeTLS(cfg.CertFile, cfg.KeyFile); err != http.ErrServerClosed {
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
