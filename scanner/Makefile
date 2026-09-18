# Makefile for Samsung Xpress M2071 / M2070 Native Scanner Engine & Swift GUI
# Target: Apple Silicon (arm64) macOS

CXX ?= clang++
SWIFTC ?= swiftc
ARCH ?= -arch arm64
SCRIPT_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
VENDOR_LIB := $(SCRIPT_DIR)/deps/lib/libusb-1.0.a
VENDOR_INC := -I$(SCRIPT_DIR)/deps/include

ifneq ($(wildcard $(VENDOR_LIB)),)
    LIBUSB_INC ?= $(VENDOR_INC)
    LIBUSB_LIB ?= $(VENDOR_LIB)
else
    BREW_PREFIX ?= $(shell brew --prefix 2>/dev/null || ([ -d /opt/homebrew ] && echo /opt/homebrew || echo /usr/local))
    LIBUSB_INC ?= $(shell [ -d "$(BREW_PREFIX)/include/libusb-1.0" ] && echo "-I$(BREW_PREFIX)/include/libusb-1.0" || echo "-I/opt/homebrew/include/libusb-1.0")
    LIBUSB_LIB ?= $(shell [ -f "$(BREW_PREFIX)/lib/libusb-1.0.a" ] && echo "$(BREW_PREFIX)/lib/libusb-1.0.a" || echo "/opt/homebrew/lib/libusb-1.0.a")
endif

CXXFLAGS ?= -O3 -std=c++14 $(ARCH) $(LIBUSB_INC) -Isrc -Wall -Wno-deprecated-declarations
LDFLAGS ?= $(ARCH) $(LIBUSB_LIB) -framework IOKit -framework CoreFoundation -framework Security -framework CoreGraphics -framework ImageIO -lobjc

SRCS = src/main.cpp \
       src/scanner_engine.cpp \
       src/transport_usb.cpp \
       src/image_writer.cpp

OBJS = $(SRCS:.cpp=.o)
ENGINE_TARGET = bin/samsung-scan-engine
APP_TARGET = Samsung\ Scanner.app/Contents/MacOS/Samsung\ Scanner
SWIFT_SRCS = $(wildcard gui-swift/Sources/*.swift)

all: $(ENGINE_TARGET) $(APP_TARGET)

$(ENGINE_TARGET): $(OBJS)
	@mkdir -p bin
	$(CXX) $(CXXFLAGS) -o $@ $(OBJS) $(LDFLAGS)
	@codesign -s - --force $@ 2>/dev/null || true
	@echo "==> Successfully built native Apple Silicon scanner engine: $@"

$(APP_TARGET): $(SWIFT_SRCS) $(ENGINE_TARGET)
	@echo "==> Building native Swift macOS Scanner Application..."
	@mkdir -p "Samsung Scanner.app/Contents/MacOS"
	@mkdir -p "Samsung Scanner.app/Contents/Resources"
	$(SWIFTC) -O -parse-as-library -framework Cocoa -framework SwiftUI -framework CoreImage -framework PDFKit -framework Vision -o "Samsung Scanner.app/Contents/MacOS/Samsung Scanner" $(SWIFT_SRCS)
	@cp -f $(ENGINE_TARGET) "Samsung Scanner.app/Contents/MacOS/"
	@chmod +x "Samsung Scanner.app/Contents/MacOS/Samsung Scanner"
	@chmod +x "Samsung Scanner.app/Contents/MacOS/samsung-scan-engine"
	@codesign -s - --force --deep "Samsung Scanner.app" 2>/dev/null || true
	@echo "==> Successfully built native Apple Silicon Swift App: Samsung Scanner.app"

src/%.o: src/%.cpp
	$(CXX) $(CXXFLAGS) -c $< -o $@

clean:
	rm -rf src/*.o bin/* gui-swift/SamsungScanner "Samsung Scanner.app/Contents/MacOS" "Samsung Scanner.app/Contents/_CodeSignature"

.PHONY: all clean
