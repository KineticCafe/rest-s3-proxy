COMMIT_HASH := $(shell git rev-parse --short HEAD 2>/dev/null)
BUILD_DATE := $(shell date +%FT%T%z)
TIMESTAMP := $(shell date +%Y%m%d%H%M%S)
LDFLAGS := -ldflags "-X main.CommitHash=$(COMMIT_HASH) -X main.BuildDate=$(BUILD_DATE)"
BUILD_TARGET := rest-s3-proxy
LOCAL_PROXY := http://localhost:8000

DIRS := $(shell go list -f {{.Dir}} ./...)

all: build

help:
	echo $(COMMIT_HASH)
	echo $(BUILD_DATE)

godeps:
ifneq ($(FAST),1)
	go get github.com/tools/godep
endif

build: godeps
	@godep go build $(LDFLAGS) -o $(BUILD_TARGET) proxy.go

clean:
	@rm -f $(BUILD_TARGET)

test-proxy: clean build
	@./$(BUILD_TARGET) &
	@echo PUT /$(BUILD_TARGET)-test/$(TIMESTAMP)
	@curl $(LOCAL_PROXY)/$(BUILD_TARGET)-test/$(TIMESTAMP) --upload-file $(BUILD_TARGET)
	@echo GET /$(BUILD_TARGET)-test/$(TIMESTAMP)
	@curl -O $(LOCAL_PROXY)/$(BUILD_TARGET)-test/$(TIMESTAMP)
	@echo Compare $(TIMESTAMP) $(BUILD_TARGET)
	@cmp $(TIMESTAMP) $(BUILD_TARGET)
	@rm $(TIMESTAMP)
	@echo DELETE /$(BUILD_TARGET)-test/$(TIMESTAMP)
	@curl -X DELETE $(LOCAL_PROXY)/$(BUILD_TARGET)-test/$(TIMESTAMP)
	@pkill $(BUILD_TARGET)

upload: upload-kcp

upload-kcp: build
	@echo "Uploading build to kcp-pkg as $(BUILD_TARGET).$(TIMESTAMP)"
	@./$(BUILD_TARGET) &
	@curl $(LOCAL_PROXY)/$(BUILD_TARGET).$(TIMESTAMP) --upload-file $(BUILD_TARGET)
	@pkill $(BUILD_TARGET)

upload-aldo: build
	@echo "Uploading build to aldo-datahub-pkg as $(BUILD_TARGET).$(TIMESTAMP)"
	@AWS_BUCKET=$(ALDO_AWS_BUCKET) AWS_REGION=$(ALDO_AWS_REGION) AWS_ACCESS_KEY_ID=$(ALDO_AWS_ACCESS_KEY_ID) AWS_SECRET_ACCESS_KEY=$(ALDO_AWS_SECRET_ACCESS_KEY) ./$(BUILD_TARGET) &
	@curl $(LOCAL_PROXY)/$(BUILD_TARGET).$(TIMESTAMP) --upload-file $(BUILD_TARGET)
	@pkill $(BUILD_TARGET)

check: fmt vet test test-race

cyclo:
	@for d in $(DIRS) ; do \
		if [ "`gocyclo -over 20 $$d | tee /dev/stderr`" ]; then \
			echo "^ cyclomatic complexity exceeds 20, refactor the code!" && echo && exit 1; \
		fi \
	done

fmt:
	@for d in $(DIRS) ; do \
		if [ "`gofmt -l $$d/*.go | tee /dev/stderr`" ]; then \
			echo "^ improperly formatted go files" && echo && exit 1; \
		fi \
	done

lint:
	@if [ "`golint ./... | tee /dev/stderr`" ]; then \
		echo "^ golint errors!" && echo && exit 1; \
	fi

test:
	go test ./...

test-race:
	go test -race ./...

vet:
	@if [ "`go vet ./... | tee /dev/stderr`" ]; then \
		echo "^ go vet errors!" && echo && exit 1; \
	fi
