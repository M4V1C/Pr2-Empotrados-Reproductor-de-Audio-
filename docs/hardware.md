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
