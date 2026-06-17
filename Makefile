SWIFT ?= swift
SWIFT_PM_FLAGS ?=
NONO_SWIFT_BUILD_ROOT ?= $(CURDIR)/.build/nono-source-build
CARGO_HOME ?= $(NONO_SWIFT_BUILD_ROOT)/cargo-home
CARGO_TARGET_DIR ?= $(NONO_SWIFT_BUILD_ROOT)/cargo-target
NONO_SWIFT_BINARY_TARGET ?= local

export NONO_SWIFT_BUILD_ROOT
export CARGO_HOME
export CARGO_TARGET_DIR
export NONO_SWIFT_BINARY_TARGET

.PHONY: artifacts artifacts-arm64 build build-arm64 clean test test-arm64 test-apply test-apply-arm64 verify-artifacts

artifacts:
	./Scripts/build-xcframework.sh

artifacts-arm64:
	./Scripts/build-xcframework.sh --arch arm64

verify-artifacts:
	./Scripts/verify-artifacts.sh

build: artifacts
	$(SWIFT) build $(SWIFT_PM_FLAGS)

build-arm64: artifacts-arm64
	$(SWIFT) build $(SWIFT_PM_FLAGS)

test: artifacts
	$(SWIFT) test $(SWIFT_PM_FLAGS)

test-arm64: artifacts-arm64
	$(SWIFT) test $(SWIFT_PM_FLAGS)

test-apply: artifacts
	NONO_REQUIRE_APPLY=1 $(SWIFT) test $(SWIFT_PM_FLAGS) --filter ApplySandboxTests

test-apply-arm64: artifacts-arm64
	NONO_REQUIRE_APPLY=1 $(SWIFT) test $(SWIFT_PM_FLAGS) --filter ApplySandboxTests

clean:
	rm -rf .build Artifacts/CNono.xcframework Artifacts/MANIFEST.json
