FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04

# Install cuDNN 9 for CUDA 12.x using NVIDIA's official APT repo
RUN apt-get update && \
    apt-get install -y wget && \
    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb && \
    dpkg -i cuda-keyring_1.1-1_all.deb && \
    apt-get update && \
    apt-get install -y cudnn cudnn-cuda-12 && \
    rm cuda-keyring_1.1-1_all.deb

# Set up environment variables for GPU access
ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV HF_HOME=/app/hf_download
ENV PATH="/venv/bin:$PATH"
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=all

# Install dependencies and Python 3.10 (better compatibility with CUDA)
RUN apt-get update && apt-get install -y \
    software-properties-common \
    python3.10 \
    python3.10-venv \
    python3.10-dev \
    python3-pip \
    git \
    ffmpeg \
    libsm6 \
    libxext6 \
    curl \
    && ln -sf /usr/bin/python3.10 /usr/bin/python3 \
    && ln -sf /usr/bin/python3 /usr/bin/python \
    && rm -rf /var/lib/apt/lists/*

# Create virtual environment with Python 3.10
RUN python3 -m venv /venv

# Install pip in virtual environment
RUN /venv/bin/pip install --upgrade pip

# Create app directory
WORKDIR /app

# Clone repository
RUN git clone https://github.com/lllyasviel/FramePack.git . && \
    mkdir -p outputs && \
    mkdir -p hf_download

# Create a fallback run script that forces CPU mode
COPY <<EOF /app/run_fallback.py
#!/usr/bin/env python3
# CPU mode fallback wrapper for FramePack
import os
import sys
import subprocess

# Force CPU mode by setting environment variables
os.environ['CUDA_VISIBLE_DEVICES'] = ''
os.environ['TORCH_DEVICE'] = 'cpu'

# Before importing PyTorch, patch the CUDA functions
import builtins
original_import = builtins.__import__

def patched_import(name, *args, **kwargs):
    module = original_import(name, *args, **kwargs)
    
    # Patch torch.cuda to avoid errors
    if name == 'torch':
        def is_available():
            return False
        
        if hasattr(module, 'cuda'):
            module.cuda.is_available = is_available
    
    return module

# Apply the import patch
builtins.__import__ = patched_import

# Now run the actual script
print("\033[33mRunning in CPU-only mode (performance will be slower)\033[0m")
print("Original command: python", " ".join(sys.argv[1:]))

# Execute the original script
if len(sys.argv) > 1:
    cmd = [sys.executable] + sys.argv[1:]
    sys.exit(subprocess.call(cmd))
EOF

RUN chmod +x /app/run_fallback.py

# Install PyTorch with CUDA 12.6 (as required by FramePack)
RUN /venv/bin/pip install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu126

# Install other dependencies
RUN /venv/bin/pip install --no-cache-dir -r requirements.txt

# Expose port for Gradio
EXPOSE 7860

# Create a GPU-optimized startup script
COPY <<EOF /start.sh
#!/bin/bash
cd /app

# Function to print colored messages
function echo_color() {
  local message="\$1"
  local color="\$2"
  echo -e "\${color}\${message}\033[0m"
}

# Color codes
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"

# Verify NVIDIA GPU is accessible
echo_color "Checking NVIDIA GPU..." "\$YELLOW"
nvidia-smi || { echo_color "ERROR: NVIDIA GPU not accessible!" "\$RED"; exit 1; }

echo_color "Setting up GPU environment..." "\$YELLOW"

# Force enable CUDA
export CUDA_VISIBLE_DEVICES=0
export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512
export NVIDIA_DRIVER_CAPABILITIES=compute,utility,video

# Verify CUDA is available through PyTorch
if /venv/bin/python -c "import torch; print('CUDA Available:', torch.cuda.is_available()); print('Device:', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'None')" | grep -q "CUDA Available: True"; then
  echo_color "✅ GPU detected: $(/venv/bin/python -c "import torch; print(torch.cuda.get_device_name(0))" 2>/dev/null)" "\$GREEN"
  echo_color "Starting FramePack with GPU acceleration" "\$GREEN"
  exec /venv/bin/python -u demo_gradio.py --server 0.0.0.0
else
  echo_color "❌ ERROR: PyTorch cannot access CUDA!" "\$RED"
  echo_color "This may be due to CUDA driver mismatch or other issues." "\$RED"
  exit 1
fi
EOF

RUN chmod +x /start.sh

# Command to run the application
ENTRYPOINT ["/start.sh"]