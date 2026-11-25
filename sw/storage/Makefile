# Libreria de almacenamiento (parser WAV + playlist) y sus pruebas.
# Uso:  make test | make wavs | make sdimg | make clean

CC      ?= gcc
CFLAGS  ?= -std=c11 -O2 -g -Wall -Wextra -Wpedantic -Werror
BUILD   := build
TOOLS   := ../../tools
SDCARD  := $(BUILD)/sdcard

SRCS := wav_meta.c playlist.c
OBJS := $(SRCS:%.c=$(BUILD)/%.o)

.PHONY: all test wavs sdimg list list-arm clean

all: $(BUILD)/libstorage.a

$(BUILD)/%.o: %.c wav_meta.h playlist.h | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/libstorage.a: $(OBJS)
	$(AR) rcs $@ $^

$(BUILD)/test_storage: tests/test_storage.c $(BUILD)/libstorage.a
	$(CC) $(CFLAGS) $< $(BUILD)/libstorage.a -o $@

test: $(BUILD)/test_storage
	./$(BUILD)/test_storage

# 11 WAV sinteticos (10 con LIST/INFO + 1 sin etiquetas) para la SD
wavs:
	python3 -I $(TOOLS)/gen_wavs.py $(SDCARD)

# Imagen FAT32 de la SD para QEMU (requiere dosfstools y mtools)
sdimg: wavs
	$(TOOLS)/mk_sdimg.sh $(SDCARD) $(BUILD)/sd.img

# Lista la playlist de $(SDCARD): nativo y en ARM de 32 bits bajo qemu-arm (modo usuario)
ARM_CC ?= arm-linux-gnueabihf-gcc

$(BUILD)/main_list: main_list.c $(BUILD)/libstorage.a
	$(CC) $(CFLAGS) $< $(BUILD)/libstorage.a -o $@

$(BUILD)/main_list_arm: main_list.c $(SRCS) wav_meta.h playlist.h | $(BUILD)
	$(ARM_CC) $(CFLAGS) -static main_list.c $(SRCS) -o $@

list: $(BUILD)/main_list wavs
	./$(BUILD)/main_list $(SDCARD)

list-arm: $(BUILD)/main_list_arm wavs
	qemu-arm ./$(BUILD)/main_list_arm $(SDCARD)

$(BUILD):
	mkdir -p $(BUILD)

clean:
	rm -rf $(BUILD)
