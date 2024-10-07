ARMV7_BINARY=dist/rmfakecloud-proxy-arm7
AARCH64_BINARY=dist/rmfakecloud-proxy-aarch64
WIN_BINARY=dist/rmfakecloud-proxy.exe
LINUX_BINARY=dist/rmfakecloud-proxy64
INSTALLER=dist/installer.sh
RM12_INSTALLER=dist/installer-rm12.sh
RMPRO_INSTALLER=dist/installer-rmpro.sh
.PHONY: clean
all: $(RMPRO_INSTALLER) $(RM12_INSTALLER) $(INSTALLER) $(WIN_BINARY) $(LINUX_BINARY)

$(LINUX_BINARY): version.go main.go
	go build -ldflags="-w -s" -o $@

$(ARMV7_BINARY): version.go main.go
	GOARCH=arm GOARM=7 go build -ldflags="-w -s" -o $@

$(AARCH64_BINARY): version.go main.go
	GOARCH=arm64 go build -ldflags="-w -s" -o $@

$(WIN_BINARY): version.go main.go
	GOOS=windows go build -ldflags="-w -s" -o $@

version.go:
	go generate

$(RMPRO_INSTALLER): $(AARCH64_BINARY) scripts/installer.sh
	cp scripts/installer.sh $@
	gzip -c $(AARCH64_BINARY) >> $@
	chmod +x $@

$(INSTALLER) $(RM12_INSTALLER): $(ARMV7_BINARY) scripts/installer.sh
	cp scripts/installer.sh $@
	gzip -c $(ARMV7_BINARY) >> $@
	chmod +x $@

clean:
	rm -fr dist
