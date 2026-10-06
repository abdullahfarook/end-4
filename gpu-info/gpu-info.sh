#!/usr/bin/env bash
# Prints: name|util%|vram_used_MiB|vram_total_MiB|gpu_clock_MHz|mem_clock_MHz|temp_C|power_W
# Prefers the external/discrete GPU (NVIDIA, then AMD); prints nothing if none has readable stats.
if command -v nvidia-smi >/dev/null; then
  nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,clocks.gr,clocks.mem,temperature.gpu,power.draw \
    --format=csv,noheader,nounits 2>/dev/null | head -1 | awk -F', *' '{printf "%s|%s|%s|%s|%s|%s|%s|%s\n",$1,$2,$3,$4,$5,$6,$7,$8}'
  exit 0
fi
for d in /sys/class/drm/card?/device; do
  [ "$(cat $d/vendor)" = 0x1002 ] && [ -r $d/mem_info_vram_total ] || continue
  h=$(echo $d/hwmon/hwmon*)
  clk=$(awk '/\*/{gsub("Mhz","",$2);print $2}' $d/pp_dpm_sclk 2>/dev/null)
  mclk=$(awk '/\*/{gsub("Mhz","",$2);print $2}' $d/pp_dpm_mclk 2>/dev/null)
  echo "AMD GPU|$(cat $d/gpu_busy_percent 2>/dev/null)|$(( $(cat $d/mem_info_vram_used)/1048576 ))|$(( $(cat $d/mem_info_vram_total)/1048576 ))|${clk:-0}|${mclk:-0}|$(( $(cat $h/temp1_input 2>/dev/null || echo 0)/1000 ))|$(( $(cat $h/power1_average 2>/dev/null || echo 0)/1000000 ))"
  exit 0
done
