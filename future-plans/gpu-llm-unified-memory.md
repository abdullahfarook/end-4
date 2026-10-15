# GPU: memory overclock and LLM VRAM+RAM offload

Status: planned, not implemented. Date: 2026-10-15.

## Hardware
- dGPU: RTX 4050 Laptop (AD107M), 6 GB GDDR6, driver 615.71, mem clock max 8001 MHz.
- iGPU: Intel UHD (Raptor Lake-P), shares system RAM.
- RAM: 23 GB (about 9 GB available with desktop running).

## 1. VRAM clock overclock (not size)
- VRAM size cannot be changed by software (soldered GDDR6).
- NVML exposes mem/graphics clock VF offsets (read works, both currently 0).
  Setting needs root: small helper via `pkexec`, like `fan-control`.
- Plan: `fan-control/gpu-oc.sh get|set <MHz>|reset|restore` with saved state,
  restored at login and after resume (like `cpu-freq.sh`).
- UI: "GPU memory offset" slider + Reset switch in the performance popup,
  range 0 to +300/+500 MHz (decide). Offsets reset on reboot.
- Caveats: power limit is N/A; bad offset = artifacts/driver reset, not damage.

## 2. "Unified" memory for LLMs
- No true unified memory on a discrete GPU (PCIe is 10-20x slower than VRAM).
- Practical approach: split layers between VRAM and RAM.
  - Ollama (simple, recommended): CUDA build via pacman (`pkexec`), enable service.
  - llama.cpp (`llama.cpp-cuda`): `--n-gpu-layers`, `--cache-type-k q8_0`, flash attention.
- Fit: Q4 up to ~7-8B fully on GPU; ~12-14B with spill (~5-15 tok/s).
  MoE models (e.g. Qwen3-30B-A3B) spill cheaply.
- Keep desktop on the Intel iGPU so the full 6 GB is free for inference.
- Widget: VRAM / RAM / layer-offload readout in the GPU info widget.

## Open decisions
- Ollama vs llama.cpp.
- Slider max (+300 vs +500 MHz).
- Whether to add the widget readout.
