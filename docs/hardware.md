# Hardware del SoC (P2 — integración)

Fuente del sistema: `tools/build_soc.tcl` → `hw/quartus/soc_system.qsys`.
Proyecto Quartus: `hw/quartus/de1_soc.qpf` (tope `de1_soc_top.v`, pines en `de1_soc.qsf`, tiempos en `de1_soc.sdc`).

## Mapa de memoria del Nios V (`cpu.data_manager`)

Las bases son fijas para todo el proyecto: cada fase agrega bloques en
huecos libres sin mover lo existente, así `system.h` no cambia.

| Bloque | Base | Fin | Tamaño | Fase | Estado |
|---|---|---|---|---|---|
| `nios_ram.s1` (código, datos, pila; arranque) | 0x0000_0000 | 0x0001_FFFF | 128 KiB | 1 | hecho |
| RAM compartida `shm_ram.s1` | 0x0002_0000 | 0x0002_FFFF | 64 KiB | 5 | reservado |
| `jtag_uart` | 0x0003_0000 | 0x0003_0007 | 8 B | 1 | hecho |
| `cpu.timer_sw_agent` (mtime/mtimecmp) | 0x0003_0040 | 0x0003_007F | 64 B | 1 | hecho |
| PIO KEY / SW / LEDR | 0x0003_0080 | 0x0003_00BF | 3 × 16 B | 2 | reservado |
| IP de audio, A/V config, ADC | 0x0003_0100 | 0x0003_01FF | — | 3–4 | reservado |
| `audio_dsp` | 0x0003_0200 | 0x0003_02FF | 256 B | 2 | reservado |
| `cpu.dm_agent` (depuración JTAG) | 0x0004_0000 | 0x0004_FFFF | 64 KiB | 1 | hecho |

`instruction_manager` solo ve `nios_ram.s1` (en 0x0).

## IRQ del Nios (`cpu.platform_irq_rx`)

| IRQ | Fuente | Fase |
|---|---|---|
| 0 | `jtag_uart` | 1 |

## Flujo de build

```
Windows (PowerShell, raíz del repo):
  powershell -ExecutionPolicy Bypass -File scripts\build-hw.ps1                         # .qsys + HDL + .sopcinfo
  powershell -ExecutionPolicy Bypass -File scripts\build-sw.ps1 sw\niosv\hw_tests\hola  # .elf -> nios_ram.hex
  Quartus -> compilar hw\quartus\de1_soc.qpf -> output_files\de1_soc.sof
  Programmer (.sof en @2) + juart-terminal

Linux (con Quartus 25.1std instalado): scripts/build-hw.sh y scripts/build-sw.sh hacen lo mismo.
```

## Notas de la fase 1 (verificado en la tarjeta, 28-11-2026)

- **El Nios V/m no implementa el CSR `mcycle`** (extensión Zicntr opcional).
  Leerlo provoca una excepción de instrucción ilegal; el `handle_trap` del HAL
  ejecuta `ebreak` y, sin depurador, el CPU queda en un bucle de traps con las
  interrupciones apagadas. Para medir tiempo se usa `mtime`, mapeado en memoria
  en `CPU_TIMER_SW_AGENT_BASE + 0` (64 bits, cuenta a 50 MHz; `mtimecmp` en +8).
- **Salida por la JTAG UART con punteros** (`sw/niosv/hw_tests/hola_ptr`):
  `DATA` en +0 (byte en [7:0]) y `CONTROL` en +4 (`WSPACE` en [31:16]); se
  espera `WSPACE > 0` antes de escribir. Es el patrón para el software del Nios
  (la especificación prohíbe `alt_*` e `IOWR`/`IORD`).
- **Cambiar solo el software** no requiere recompilar todo:
  `quartus_cdb de1_soc -c de1_soc --update_mif` y `quartus_asm de1_soc -c de1_soc`
  reemplazan el contenido de la RAM en el `.sof` en menos de un minuto.
- Programar: `quartus_pgm -c "DE-SoC [USB-1]" -m jtag -o "p;output_files/de1_soc.sof@2"`.
  Terminal: `juart-terminal -c 1 -d 2 -i 0`.
