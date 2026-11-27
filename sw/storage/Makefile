# Libreria de almacenamiento (parser WAV + playlist + lector de muestras) y sus pruebas.
# Uso:  make test | wavs | sdimg | list | read | list-arm | read-arm | dist | clean

CC      ?= gcc
CFLAGS  ?= -std=c11 -O2 -g -Wall -Wextra -Wpedantic -Werror
BUILD   := build
TOOLS   := ../../tools
SDCARD  := $(BUILD)/sdcard

# Compilacion cruzada para el HPS (Cortex-A9, ARM de 32 bits con FPU)
ARM_CC    ?= arm-linux-gnueabihf-gcc
ARM_AR    ?= arm-linux-gnueabihf-ar
ARM_STRIP ?= arm-linux-gnueabihf-strip
ARM_BUILD := $(BUILD)/arm
DIST      := $(BUILD)/dist/storage-hps

SRCS := wav_meta.c playlist.c track_reader.c
HDRS := wav_meta.h playlist.h track_reader.h
OBJS     := $(SRCS:%.c=$(BUILD)/%.o)
ARM_OBJS := $(SRCS:%.c=$(ARM_BUILD)/%.o)

.PHONY: all test wavs sdimg list read list-arm read-arm dist clean

all: $(BUILD)/libstorage.a

# ---- nativo (PC) ----
$(BUILD)/%.o: %.c $(HDRS) | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/libstorage.a: $(OBJS)
	$(AR) rcs $@ $^

$(BUILD)/test_storage: tests/test_storage.c $(BUILD)/libstorage.a $(HDRS)
	$(CC) $(CFLAGS) $< $(BUILD)/libstorage.a -o $@

test: $(BUILD)/test_storage
	./$(BUILD)/test_storage

$(BUILD)/main_list: main_list.c $(BUILD)/libstorage.a
	$(CC) $(CFLAGS) $< $(BUILD)/libstorage.a -o $@

$(BUILD)/main_read: main_read.c $(BUILD)/libstorage.a
	$(CC) $(CFLAGS) $< $(BUILD)/libstorage.a -o $@

# 11 WAV sinteticos (10 con LIST/INFO + 1 sin etiquetas) para la SD
wavs:
	python3 -I $(TOOLS)/gen_wavs.py $(SDCARD)

# Imagen FAT32 de la SD para QEMU (requiere dosfstools y mtools)
sdimg: wavs
	$(TOOLS)/mk_sdimg.sh $(SDCARD) $(BUILD)/sd.img

list: $(BUILD)/main_list wavs
	./$(BUILD)/main_list $(SDCARD)

read: $(BUILD)/main_read wavs
	./$(BUILD)/main_read $(SDCARD)

# ---- ARM de 32 bits (binarios estaticos: corren en el HPS sin librerias extra) ----
$(ARM_BUILD)/%.o: %.c $(HDRS) | $(ARM_BUILD)
	$(ARM_CC) $(CFLAGS) -c $< -o $@

$(ARM_BUILD)/libstorage.a: $(ARM_OBJS)
	$(ARM_AR) rcs $@ $^

$(BUILD)/main_list_arm: main_list.c $(ARM_BUILD)/libstorage.a
	$(ARM_CC) $(CFLAGS) -static $< $(ARM_BUILD)/libstorage.a -o $@

$(BUILD)/main_read_arm: main_read.c $(ARM_BUILD)/libstorage.a
	$(ARM_CC) $(CFLAGS) -static $< $(ARM_BUILD)/libstorage.a -o $@

# bajo qemu-arm (modo usuario)
list-arm: $(BUILD)/main_list_arm wavs
	qemu-arm ./$(BUILD)/main_list_arm $(SDCARD)

read-arm: $(BUILD)/main_read_arm wavs
	qemu-arm ./$(BUILD)/main_read_arm $(SDCARD)

# ---- paquete para quien integre (ARM): headers, libreria, binarios y guia ----
dist: $(ARM_BUILD)/libstorage.a $(BUILD)/main_list_arm $(BUILD)/main_read_arm README.md
	rm -rf $(DIST)
	mkdir -p $(DIST)/include $(DIST)/lib $(DIST)/bin $(DIST)/tools
	cp $(HDRS) $(DIST)/include/
	cp $(ARM_BUILD)/libstorage.a $(DIST)/lib/
	cp $(BUILD)/main_list_arm $(DIST)/bin/main_list
	cp $(BUILD)/main_read_arm $(DIST)/bin/main_read
	$(ARM_STRIP) $(DIST)/bin/main_list $(DIST)/bin/main_read
	cp README.md $(DIST)/
	cp $(TOOLS)/gen_wavs.py $(TOOLS)/mk_sdimg.sh $(DIST)/tools/
	tar -czf $(BUILD)/storage-hps.tar.gz -C $(BUILD)/dist storage-hps
	@echo "Paquete: $(BUILD)/storage-hps.tar.gz"

$(BUILD) $(ARM_BUILD):
	mkdir -p $@

clean:
	rm -rf $(BUILD)
