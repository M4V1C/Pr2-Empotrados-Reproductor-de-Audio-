# Lado HPS de la comunicacion HPS <-> Nios V: protocolo, reproductor y simulacion en el PC.
# Uso:  make test | nios-check | clean
#
# 'test' corre el reproductor del HPS y un Nios simulado (la misma libreria shm_nios.c que
# usara el main real) como dos hilos sobre un arreglo que hace de RAM compartida.

CC      ?= gcc
CFLAGS  ?= -std=c11 -O2 -g -Wall -Wextra -Wpedantic -Werror
BUILD   := build
STORAGE := ../storage
LIBSTORAGE := $(STORAGE)/build/libstorage.a

SRCS := shm_hps.c shm_sink.c player.c ../niosv/src/shm_nios.c
HDRS := shm_hps.h shm_sink.h player.h ../common/shm_protocol.h ../niosv/src/shm_nios.h

# Compilador cruzado del Nios V (viene con Quartus: source scripts/env.sh del Taller 09)
RISCV_PREFIX ?= riscv32-unknown-elf-

.PHONY: all test nios-check clean

all: $(BUILD)/test_comm

$(LIBSTORAGE): $(wildcard $(STORAGE)/*.c $(STORAGE)/*.h)
	$(MAKE) -C $(STORAGE) all

$(BUILD)/test_comm: tests/test_comm.c $(SRCS) $(HDRS) $(LIBSTORAGE) | $(BUILD)
	$(CC) $(CFLAGS) -pthread tests/test_comm.c $(SRCS) $(LIBSTORAGE) -o $@

test: $(BUILD)/test_comm
	./$(BUILD)/test_comm

# shm_nios.c debe compilar para el Nios V/m (RV32I, sin multiplicador), sin libc y sin llamar
# a rutinas de libgcc como __mulsi3 o __divsi3.
nios-check: | $(BUILD)
	$(RISCV_PREFIX)gcc -march=rv32i -mabi=ilp32 -ffreestanding -O2 -Wall -Wextra -Werror \
	    -c ../niosv/src/shm_nios.c -o $(BUILD)/shm_nios_rv32.o
	@if $(RISCV_PREFIX)nm -u $(BUILD)/shm_nios_rv32.o | grep -q .; then \
	    echo "FALLO: shm_nios.c tiene simbolos externos:"; \
	    $(RISCV_PREFIX)nm -u $(BUILD)/shm_nios_rv32.o; exit 1; \
	else echo "OK: shm_nios.c compila para RV32I sin dependencias externas"; fi

$(BUILD):
	mkdir -p $@

clean:
	rm -rf $(BUILD)
