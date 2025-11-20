//go:generate go run generate/versioninfo.go

// secure is a super simple TLS termination proxy
package main

import (
	"context"
	"crypto/tls"
	"flag"
	"fmt"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"

	"gopkg.in/yaml.v3"
)

type Config struct {
	CertFile       string `yaml:"cert"`
	KeyFile        string `yaml:"key"`
	Upstream       string `yaml:"upstream"`
	Addr           string `yaml:"addr"`
	CFClientID     string `yaml:"cf_client_id"`
	CFClientSecret string `yaml:"cf_client_secret"`
	ClientCertFile string `yaml:"client_cert"`
	ClientKeyFile  string `yaml:"client_key"`
}

var (
	version    bool
	configFile string
)

// normalizeCFToken strips common prefixes from Cloudflare token input
// Accepts formats like: "CF-Access-Client-Id: value", "cf-access-client-id: value", or just "value"
func normalizeCFToken(input, tokenType string) string {
	if input == "" {
		return ""
	}

	input = strings.TrimSpace(input)

	// List of possible prefixes to strip (case-insensitive)
	prefixes := []string{
		"cf-access-client-id:",
		"cf-access-client-secret:",
		"cf-access-client-id=",
		"cf-access-client-secret=",
	}

	lowerInput := strings.ToLower(input)
	for _, prefix := range prefixes {
		if strings.HasPrefix(lowerInput, prefix) {
			input = strings.TrimSpace(input[len(prefix):])
			break
		}
	}

	return input
}

func getConfig() (config *Config, err error) {
	cfg := Config{}
	flag.StringVar(&configFile, "c", "", "config file")
	flag.StringVar(&cfg.Addr, "addr", ":443", "listen address")
	flag.StringVar(&cfg.CertFile, "cert", "", "path to cert file")
	flag.StringVar(&cfg.KeyFile, "key", "", "path to key file")
	flag.StringVar(&cfg.CFClientID, "cf-client-id", "", "Cloudflare Access Client ID (optional)")
	flag.StringVar(&cfg.CFClientSecret, "cf-client-secret", "", "Cloudflare Access Client Secret (optional)")
	flag.StringVar(&cfg.ClientCertFile, "client-cert", "", "path to client cert file for mTLS (optional)")
	flag.StringVar(&cfg.ClientKeyFile, "client-key", "", "path to client key file for mTLS (optional)")
	flag.BoolVar(&version, "version", false, "print version string and exit")

	flag.Usage = func() {
		fmt.Fprintf(flag.CommandLine.Output(),
			"usage: %s -c [config.yml] [-addr host:port] -cert certfile -key keyfile [-client-cert file] [-client-key file] [-cf-client-id value] [-cf-client-secret value] [-version] upstream\n",
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
		data, err = os.ReadFile(configFile)

		if err != nil {
			return
		}
		err = yaml.Unmarshal(data, &cfg)
		if err != nil {
			return nil, fmt.Errorf("cant parse config, %v", err)
		}
		if _, err := strconv.Atoi(cfg.Addr); err == nil {
			cfg.Addr = ":" + cfg.Addr

		}
		return &cfg, nil
	}

	// Normalize Cloudflare tokens
	cfg.CFClientID = normalizeCFToken(cfg.CFClientID, "id")
	cfg.CFClientSecret = normalizeCFToken(cfg.CFClientSecret, "secret")

	if flag.NArg() == 1 {
		cfg.Upstream = flag.Arg(0)
	} else {
		flag.Usage()
		os.Exit(2)
	}

	return &cfg, nil
}

func singleJoiningSlash(a, b string) string {
	aslash := strings.HasSuffix(a, "/")
	bslash := strings.HasPrefix(b, "/")
	switch {
	case aslash && bslash:
		return a + b[1:]
	case !aslash && !bslash:
		return a + "/" + b
	}
	return a + b
}

func joinURLPath(a, b *url.URL) (path, rawpath string) {
	if a.RawPath == "" && b.RawPath == "" {
		return singleJoiningSlash(a.Path, b.Path), ""
	}
	// Same as singleJoiningSlash, but uses EscapedPath to determine
	// whether a slash should be added
	apath := a.EscapedPath()
	bpath := b.EscapedPath()

	aslash := strings.HasSuffix(apath, "/")
	bslash := strings.HasPrefix(bpath, "/")

	switch {
	case aslash && bslash:
		return a.Path + b.Path[1:], apath + bpath[1:]
	case !aslash && !bslash:
		return a.Path + "/" + b.Path, apath + "/" + bpath
	}
	return a.Path + b.Path, apath + bpath
}

func _main() error {
	cfg, err := getConfig()
	if err != nil {
		return err
	}

	upstream, err := url.Parse(cfg.Upstream)
	if err != nil {
		return fmt.Errorf("invalid upstream address: %v", err)
	}

	upstreamQuery := upstream.RawQuery
	director := func(req *http.Request) {
		req.URL.Scheme = upstream.Scheme
		req.Host = upstream.Host
		req.URL.Host = upstream.Host
		req.URL.Path, req.URL.RawPath = joinURLPath(upstream, req.URL)
		if upstreamQuery == "" || req.URL.RawQuery == "" {
			req.URL.RawQuery = upstreamQuery + req.URL.RawQuery
		} else {
			req.URL.RawQuery = upstreamQuery + "&" + req.URL.RawQuery
		}
		if _, ok := req.Header["User-Agent"]; !ok {
			// explicitly disable User-Agent so it's not set to default value
			req.Header.Set("User-Agent", "")
		}

		if cfg.CFClientID != "" && cfg.CFClientSecret != "" {
			req.Header.Set("CF-Access-Client-Id", cfg.CFClientID)
			req.Header.Set("CF-Access-Client-Secret", cfg.CFClientSecret)
		}
	}

	var transport *http.Transport
	if cfg.ClientCertFile != "" && cfg.ClientKeyFile != "" {
		clientCert, err := tls.LoadX509KeyPair(cfg.ClientCertFile, cfg.ClientKeyFile)
		if err != nil {
			return fmt.Errorf("failed to load client certificate: %v", err)
		}

		tlsConfig := &tls.Config{
			Certificates: []tls.Certificate{clientCert},
		}

		transport = &http.Transport{
			TLSClientConfig: tlsConfig,
		}
		log.Printf("mTLS enabled with client-cert=%s client-key=%s", cfg.ClientCertFile, cfg.ClientKeyFile)
	} else {
		transport = http.DefaultTransport.(*http.Transport)
	}

	srv := http.Server{
		Handler: &httputil.ReverseProxy{
			Director:  director,
			Transport: transport,
		},
		Addr: cfg.Addr,
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

	log.Printf("cert-file=%s key-file=%s listen-addr=%s upstream-url=%s", cfg.CertFile, cfg.KeyFile, srv.Addr, upstream.String())
	if cfg.CFClientID != "" && cfg.CFClientSecret != "" {
		log.Printf("cf-client-id=%s cf-client-secret=%s", cfg.CFClientID, strings.Repeat("*", len(cfg.CFClientSecret)))
	}
	if cfg.ClientCertFile != "" && cfg.ClientKeyFile != "" {
		log.Printf("client-cert=%s client-key=%s", cfg.ClientCertFile, cfg.ClientKeyFile)
	}

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
