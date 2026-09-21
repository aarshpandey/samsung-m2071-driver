# Makefile for Samsung Xpress M2070 / M2071 Series macOS Apple Silicon Driver
# Target architecture: Apple Silicon (arm64)
# macOS version: Darwin / macOS (native arm64)

CXX ?= clang++
ARCH ?= -arch arm64
CXXFLAGS ?= -O3 -std=c++14 $(ARCH) -Iinclude -DDISABLE_JBIG=1 -DVERSION=\"1.0.2-arm64\" -DCACHESIZE=30 -DTHREADS=2 -Wall -Wno-deprecated-declarations
LDFLAGS ?= $(ARCH) -lcups

SRCS = src/algo0x0d.cpp \
       src/algo0x0e.cpp \
       src/algo0x11.cpp \
       src/algorithm.cpp \
       src/band.cpp \
       src/bandplane.cpp \
       src/cache.cpp \
       src/colors.cpp \
       src/compress.cpp \
       src/core.cpp \
       src/document.cpp \
       src/page.cpp \
       src/ppdfile.cpp \
       src/printer.cpp \
       src/qpdl.cpp \
       src/rastertoqpdl.cpp \
       src/rendering.cpp \
       src/request.cpp \
       src/semaphore.cpp

OBJS = $(SRCS:.cpp=.o)
TARGET = bin/rastertoqpdl

all: $(TARGET)

$(TARGET): $(OBJS)
	@mkdir -p bin
	$(CXX) $(CXXFLAGS) -o $@ $(OBJS) $(LDFLAGS)
	@codesign -s - --force $@ 2>/dev/null || true
	@echo "==> Successfully built native Apple Silicon arm64 filter: $@"

src/%.o: src/%.cpp
	$(CXX) $(CXXFLAGS) -c $< -o $@

clean:
	rm -f src/*.o bin/*

.PHONY: all clean
