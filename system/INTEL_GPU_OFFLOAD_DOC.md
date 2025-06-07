# Offloading Background Compute to Intel GPU on Hybrid NVIDIA System

This guide explains how to leverage the integrated Intel UHD Graphics 630 GPU on a hybrid laptop system that uses NVIDIA as the primary GPU (e.g., via `prime-select nvidia`). While NVIDIA handles the display, Intel can be used for background compute like LLM inference, video transcoding, or OpenCL/VAAPI tasks.

## 🔧 System Setup Summary

* **NVIDIA**: primary rendering GPU (via `prime-select nvidia`)
* **Intel GPU**: still active, available for compute via OpenCL, VAAPI, or OpenVINO
* **Power not a concern** (always plugged in)

## ✅ Prerequisites

Install required drivers and tools:

```bash
sudo apt install -y intel-opencl-icd intel-media-va-driver-non-free clinfo vainfo
```

Verify Intel GPU is detected:

```bash
clinfo | grep "Device"
vainfo
```

## 🧠 What You Can Offload to Intel GPU

| Task                | Tool                     | Notes                               |
| ------------------- | ------------------------ | ----------------------------------- |
| LLM Inference       | `llama.cpp`, ONNX        | Use OpenCL / OpenVINO backends      |
| Video Encoding      | `ffmpeg` + `vaapi`       | H.264, H.265, JPEG, VP8/9 supported |
| General Compute     | OpenCL tasks             | GPU-accelerated CLI tools/scripts   |
| AI Media Processing | OpenVINO, VAAPI pipeline | Lower-priority background tasks     |

## 🚀 Usage Examples

### LLM Background Inference (llama.cpp)

Ensure you compile with OpenCL:

```bash
make LLAMA_CLBLAST=1
```

Run with:

```bash
./main -m models/7B/ggml-model.bin --ctx-size 1024 --threads 8 --n-gpu-layers 0 --use-opencl
```

### Video Transcoding Offload

Use Intel’s VAAPI for hardware-accelerated transcoding:

```bash
ffmpeg -hwaccel vaapi -vaapi_device /dev/dri/renderD128 \
  -i input.mp4 -vf 'format=nv12,hwupload' -c:v h264_vaapi output.mp4
```

### ONNX Runtime with OpenVINO

```python
import onnxruntime as ort
sess = ort.InferenceSession("model.onnx", providers=["OpenVINOExecutionProvider"])
```

---

## 🛠️ Helper Scripts

### `run-on-intel.sh` (Generic Launcher)

```bash
#!/bin/bash
# Usage: ./run-on-intel.sh <command> [args]

export GPU_FORCE_INTEL=1
export OCL_ICD_DEFAULT_PLATFORM="Intel"

exec "$@"
```

### `llm-on-intel.sh`

```bash
#!/bin/bash
# Usage: ./llm-on-intel.sh <llama.cpp args>

export GPU_FORCE_INTEL=1
export OCL_ICD_DEFAULT_PLATFORM="Intel"
cd /path/to/llama.cpp
exec ./main --use-opencl "$@"
```

### `transcode-on-intel.sh`

```bash
#!/bin/bash
# Usage: ./transcode-on-intel.sh input.mp4 output.mp4

INPUT="$1"
OUTPUT="$2"
ffmpeg -hwaccel vaapi -vaapi_device /dev/dri/renderD128 \
  -i "$INPUT" -vf 'format=nv12,hwupload' -c:v h264_vaapi "$OUTPUT"
```

### `gpu-load-watch.sh`

```bash
#!/bin/bash
# Live monitor GPU usage for Intel and NVIDIA
watch -n 2 '
  echo "\n=== Intel (iGPU) ===";
  intel_gpu_top -l 1 | head -20;
  echo "\n=== NVIDIA (dGPU) ===";
  nvidia-smi;
'
```

Make them executable:

```bash
chmod +x *.sh
```

---

## 🧼 Troubleshooting

* **Intel GPU not detected?** Run `clinfo`, check dmesg for i915 errors.
* **Conflicting drivers?** Ensure nouveau is blacklisted and Intel driver (iHD) is active.
* **ONNX slow or fails?** Make sure `onnxruntime-openvino` is installed.

---

## 🧭 Summary

You can now fully utilize your Intel GPU for auxiliary work while reserving your NVIDIA GPU for real-time or high-priority tasks. This hybrid config gives you a workstation-class edge without any added hardware.

Let background workloads run smart, slow, and off-screen.

