#!/bin/bash

# framepack.sh - Docker-based launcher for FramePack with GPU support
# This script checks for prerequisites and runs FramePack in a Docker container
# with NVIDIA GPU support in WSL2

# Configuration
IMAGE_NAME="framepack:latest"
CONTAINER_NAME="framepack-gpu"
PORT=7860
REPO_DIR="$(dirname "$(readlink -f "$0")")" # Path to current directory

# Set up colored output
YELLOW="\033[1;33m"
GREEN="\033[1;32m"
RED="\033[1;31m"
BLUE="\033[1;34m"
CYAN="\033[1;36m"
NC="\033[0m" # No Color

# Function to display colored output
echo_color() {
  echo -e "${2}${1}${NC}"
}

# Function to check if a command exists
command_exists() {
  command -v "$1" > /dev/null 2>&1
}

# Clean up on exit
cleanup() {
  echo_color "\nCleaning up..." "$YELLOW"
  if [ ! -z "$CONTAINER_ID" ]; then
    echo_color "Stopping container $CONTAINER_ID..." "$YELLOW"
    docker stop "$CONTAINER_ID" >/dev/null 2>&1
  fi
  exit 0
}

# Register cleanup on Ctrl+C
trap cleanup SIGINT SIGTERM

# Display banner
echo_color "\n╔════════════════════════════════════════════════════╗" "$CYAN"
echo_color "║             FRAMEPACK LAUNCHER                 ║" "$CYAN"
echo_color "╚════════════════════════════════════════════════════╝" "$CYAN"
echo_color "" ""

# Step 1: Check prerequisites
echo_color "Step 1: Checking prerequisites..." "$YELLOW"

# Check for Docker
if ! command_exists docker; then
  echo_color "❌ Docker not found. Please install Docker." "$RED"
  echo_color "Visit: https://docs.docker.com/get-docker/" "$YELLOW"
  exit 1
else
  echo_color "✅ Docker is installed." "$GREEN"
fi

# Check for NVIDIA GPU
if ! command_exists nvidia-smi; then
  echo_color "❌ NVIDIA drivers not found. GPU acceleration requires NVIDIA drivers." "$RED"
  echo_color "Visit: https://docs.nvidia.com/cuda/wsl-user-guide/index.html" "$YELLOW"
  
  read -p "Continue without GPU support? (y/n): " choice
  if [[ ! "$choice" =~ ^[Yy]$ ]]; then
    echo_color "Exiting. Please install NVIDIA drivers and try again." "$YELLOW"
    exit 1
  fi
  USE_GPU=false
else
  echo_color "✅ NVIDIA drivers are installed." "$GREEN"
  USE_GPU=true
  
  # Test GPU access in Docker
  echo_color "Testing GPU access in Docker..." "$YELLOW"
  if ! docker run --rm --gpus all nvidia/cuda:12.1.1-base-ubuntu22.04 nvidia-smi > /dev/null 2>&1; then
    echo_color "❌ Docker cannot access GPU." "$RED"
    
    # Check if running in WSL2
    if grep -q "microsoft" /proc/version 2>/dev/null; then
      echo_color "ℹ️ Running in WSL2 environment" "$YELLOW"
      echo_color "Please ensure:" "$YELLOW"
      echo_color "1. Docker Desktop is running on Windows" "$YELLOW"
      echo_color "2. WSL Integration is enabled in Docker Desktop" "$YELLOW"
      echo_color "3. GPU settings are enabled in Docker Desktop Resources section" "$YELLOW"
    fi
    
    read -p "Continue without GPU support? (y/n): " choice
    if [[ ! "$choice" =~ ^[Yy]$ ]]; then
      echo_color "Exiting. Please fix GPU access issues and try again." "$YELLOW"
      exit 1
    fi
    USE_GPU=false
  else
    echo_color "✅ GPU is accessible to Docker." "$GREEN"
  fi
fi

# Create outputs directory if it doesn't exist
mkdir -p "$REPO_DIR/outputs"

# Step 2: Check for Docker image
echo_color "\nStep 2: Checking Docker image..." "$YELLOW"

# Check if Docker image exists
if docker images -q "$IMAGE_NAME" > /dev/null; then
  echo_color "✅ FramePack Docker image found." "$GREEN"
else
  echo_color "ℹ️ FramePack Docker image not found. Building..." "$YELLOW"
  
  # Check if Dockerfile exists
  if [ ! -f "$REPO_DIR/Dockerfile" ]; then
    echo_color "❌ Dockerfile not found!" "$RED"
    exit 1
  fi
  
  # Build the Docker image
  echo_color "Building Docker image (this may take a while)..." "$YELLOW"
  if ! docker build -t "$IMAGE_NAME" "$REPO_DIR"; then
    echo_color "❌ Failed to build Docker image!" "$RED"
    exit 1
  fi
  
  echo_color "✅ Docker image built successfully." "$GREEN"
fi

# Step 3: Check for running containers and port availability
echo_color "\nStep 3: Managing containers..." "$YELLOW"

# Stop existing containers with the same name
if docker ps -a -q --filter "name=^/${CONTAINER_NAME}$" | grep -q .; then
  echo_color "ℹ️ Found existing FramePack container." "$YELLOW"
  read -p "Stop and remove it? (y/n): " choice
  if [[ "$choice" =~ ^[Yy]$ ]]; then
    echo_color "Stopping and removing existing container..." "$YELLOW"
    docker stop "$CONTAINER_NAME" >/dev/null 2>&1
    docker rm "$CONTAINER_NAME" >/dev/null 2>&1
  else
    # Check if it's running
    if docker ps -q --filter "name=^/${CONTAINER_NAME}$" | grep -q .; then
      echo_color "✅ Container is already running." "$GREEN"
      echo_color "🌐 Access it at: http://localhost:$PORT" "$GREEN"
      docker logs -f "$CONTAINER_NAME"
      exit 0
    fi
  fi
fi

# Check if the port is already in use
if docker ps -q --filter "publish=$PORT" | grep -q .; then
  echo_color "⚠️ Port $PORT is already in use by another container." "$YELLOW"
  CONTAINER_USING_PORT=$(docker ps --filter "publish=$PORT" --format "{{.Names}}")
  echo_color "Container '$CONTAINER_USING_PORT' is using port $PORT." "$YELLOW"
  
  read -p "Stop that container and use port $PORT? (y/n): " choice
  if [[ "$choice" =~ ^[Yy]$ ]]; then
    echo_color "Stopping container..." "$YELLOW"
    docker stop "$CONTAINER_USING_PORT" >/dev/null 2>&1
  else
    # Find an available port
    PORT=7861
    while docker ps -q --filter "publish=$PORT" | grep -q .; do
      PORT=$((PORT + 1))
    done
    echo_color "Using alternative port: $PORT" "$GREEN"
  fi
fi

# Step 4: Launch the container
echo_color "\nStep 4: Launching FramePack..." "$YELLOW"

# Prepare the Docker run command based on GPU availability
if [ "$USE_GPU" = true ]; then
  echo_color "Starting with GPU acceleration..." "$GREEN"
  docker_run_cmd="docker run -d \
    --name \"$CONTAINER_NAME\" \
    --gpus all \
    -e NVIDIA_VISIBLE_DEVICES=all \
    -e NVIDIA_DRIVER_CAPABILITIES=all \
    -p $PORT:7860 \
    -v \"$REPO_DIR/outputs:/app/outputs\" \
    \"$IMAGE_NAME\""
  GPU_MODE="GPU"
else
  echo_color "Starting in CPU-only mode (slower performance)..." "$YELLOW"
  docker_run_cmd="docker run -d \
    --name \"$CONTAINER_NAME\" \
    -p $PORT:7860 \
    -v \"$REPO_DIR/outputs:/app/outputs\" \
    \"$IMAGE_NAME\""
  GPU_MODE="CPU"
fi

# Execute the Docker run command
echo_color "Executing: $docker_run_cmd" "$YELLOW"
CONTAINER_ID=$(eval $docker_run_cmd)

# Check if container started successfully
if [ -z "$CONTAINER_ID" ] || ! docker ps -q --filter "id=$CONTAINER_ID" | grep -q .; then
  echo_color "❌ Failed to start container!" "$RED"
  if [ ! -z "$CONTAINER_ID" ]; then
    echo_color "Container logs:" "$YELLOW"
    docker logs "$CONTAINER_ID"
    docker rm "$CONTAINER_ID" >/dev/null 2>&1
  fi
  exit 1
fi

echo_color "✅ Container started with ID: $CONTAINER_ID" "$GREEN"

# Step 5: Monitor container startup
echo_color "\nStep 5: Monitoring startup..." "$YELLOW"
echo_color "Waiting for application to start..." "$YELLOW"
echo_color "This may take a few minutes as models are downloaded..." "$YELLOW"

# Display spinner while waiting
spinner=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
spin=0
max_wait=300  # Wait up to 5 minutes (model downloads take time)

for ((i=0; i<max_wait; i++)); do
  # Check if container is still running
  if ! docker ps -q --filter "id=$CONTAINER_ID" | grep -q .; then
    echo_color "\n❌ Container stopped unexpectedly!" "$RED"
    echo_color "Container logs:" "$YELLOW"
    docker logs "$CONTAINER_ID" | tail -n 30
    docker rm "$CONTAINER_ID" >/dev/null 2>&1
    exit 1
  fi
  
  # Check if application is ready
  if docker logs "$CONTAINER_ID" 2>&1 | grep -q "Running on local URL:  http://0.0.0.0:7860"; then
    clear
    echo_color "╭───────────────────────────────────────────────────────────╮" "$GREEN"
    echo_color "│                  FRAMEPACK IS READY                     │" "$GREEN"
    echo_color "╰───────────────────────────────────────────────────────────╯" "$GREEN"
    echo_color "" ""
    
    if [ "$GPU_MODE" = "GPU" ]; then
      echo_color "💻 Running with GPU acceleration" "$GREEN"
    else
      echo_color "💻 Running in CPU-only mode (slower performance)" "$YELLOW"
    fi
    
    echo_color "🌐 Access the web interface at: http://localhost:$PORT" "$GREEN"
    echo_color "💾 Generated outputs will be saved to: $REPO_DIR/outputs" "$GREEN"
    echo_color "📋 Press Ctrl+C to stop the container" "$YELLOW"
    echo_color "" ""
    
    # Show container logs
    docker logs -f "$CONTAINER_ID"
    break
  fi
  
  # Update spinner
  spin_char="${spinner[$((spin % 10))]}"
  spin=$((spin + 1))
  printf "\r${YELLOW}%s Initializing FramePack... (This may take several minutes for model downloads)${NC}" "$spin_char"
  sleep 1
done

# If we reach here without finding the ready message, but container is still running
if [ $i -eq $max_wait ] && docker ps -q --filter "id=$CONTAINER_ID" | grep -q .; then
  echo_color "\n⚠️ Container is still running but startup message not detected." "$YELLOW"
  echo_color "This could mean models are still downloading or initializing." "$YELLOW"
  echo_color "🌐 Try accessing the application at: http://localhost:$PORT" "$GREEN"
  echo_color "💾 Generated outputs will be saved to: $REPO_DIR/outputs" "$GREEN"
  echo_color "📋 Press Ctrl+C to stop the container" "$YELLOW"
  echo_color "" ""
  
  # Show container logs
  docker logs -f "$CONTAINER_ID"
fi

# End of script
echo_color "Checking prerequisites..." "${YELLOW}"

# Check for Docker
if ! command_exists docker; then
  echo_color "❌ Docker not found. Please install Docker." "${RED}"
  echo_color "Visit: https://docs.docker.com/get-docker/" "${YELLOW}"
  exit 1
else
  echo_color "✅ Docker is installed." "${GREEN}"
fi

# Check for NVIDIA drivers
if ! command_exists nvidia-smi; then
  echo_color "⚠️ NVIDIA drivers not found. GPU acceleration will not be available." "${YELLOW}"
  echo_color "Visit: https://docs.nvidia.com/cuda/wsl-user-guide/index.html" "${YELLOW}"
  USE_GPU=false
else
  echo_color "✅ NVIDIA drivers are installed." "${GREEN}"
  USE_GPU=true
  
  # In WSL2, we need to ensure Docker Desktop is running with GPU support
  if grep -q "microsoft" /proc/version 2>/dev/null; then
    echo_color "ℹ️ Running in WSL2 environment" "${YELLOW}"
    echo_color "ℹ️ Checking if GPU is accessible from Docker..." "${YELLOW}"
    
    # Test if Docker can access the GPU
    if ! docker run --rm --gpus all nvidia/cuda:12.1.1-base-ubuntu22.04 nvidia-smi > /dev/null 2>&1; then
      echo_color "⚠️ Docker cannot access NVIDIA GPU in WSL2" "${YELLOW}"
      echo_color "Please ensure:" "${YELLOW}"
      echo_color "1. Docker Desktop is running on Windows" "${YELLOW}"
      echo_color "2. WSL Integration is enabled in Docker Desktop" "${YELLOW}"
      echo_color "3. GPU settings are enabled in Docker Desktop Resources section" "${YELLOW}"
      
      read -p "Continue without GPU support? (y/n): " choice
      if [[ "$choice" =~ ^[Yy]$ ]]; then
        USE_GPU=false
      else
        exit 1
      fi
    else
      echo_color "✅ GPU is accessible to Docker." "${GREEN}"
    fi
  fi
fi

# Create outputs directory if it doesn't exist
mkdir -p "$REPO_DIR/outputs"

# Check if we're running in WSL2
is_wsl2=false
if grep -q "microsoft" /proc/version 2>/dev/null; then
  is_wsl2=true
fi

# Function to check GPU access
check_gpu_access() {
  # Try to run nvidia-smi
  if nvidia-smi > /dev/null 2>&1; then
    echo_color "NVIDIA GPU detected and accessible." "${GREEN}"
    return 0
  else
    return 1
  fi
}

# Check for Docker Desktop in WSL2
check_docker_desktop() {
  # Check if Docker is running as a Windows process
  if [ "$is_wsl2" = true ] && ! check_gpu_access; then
    echo_color "⚠️ GPU drivers detected but appear inaccessible from WSL2." "${YELLOW}"
    echo_color "This is typically caused by Docker Desktop not running on Windows." "${YELLOW}"
    echo_color "To enable GPU acceleration:" "${GREEN}"
    echo_color "1. Make sure Docker Desktop is running on Windows" "${GREEN}"
    echo_color "2. Ensure WSL2 GPU support is enabled in Docker Desktop settings" "${GREEN}"
    echo_color "3. Restart WSL2 if needed with: wsl --shutdown" "${GREEN}"
    echo_color "" ""
    read -p "Would you like to continue with CPU-only mode? (y/n): " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
      echo_color "Continuing with CPU-only mode." "${YELLOW}"
      return 1
    else
      echo_color "Please start Docker Desktop on Windows and run this script again." "${YELLOW}"
      exit 1
    fi
  fi
  return 0
}

# Check for nvidia-smi (NVIDIA drivers)
if ! command_exists nvidia-smi; then
  echo_color "NVIDIA drivers not found. Please install NVIDIA drivers for your GPU." "${RED}"
  echo_color "Visit: https://docs.nvidia.com/cuda/wsl-user-guide/index.html" "${YELLOW}"
  echo_color "Continuing in CPU-only mode..." "${YELLOW}"
  use_gpu=false
else
  echo_color "NVIDIA drivers are installed." "${GREEN}"
  # Check if Docker Desktop is running and GPU is accessible
  check_docker_desktop
  gpu_available=$?
  
  # Check for NVIDIA Container Toolkit
  if ! grep -q "nvidia-container-toolkit" <<< "$(apt list --installed 2>/dev/null)"; then
    echo_color "NVIDIA Container Toolkit not found. Installing..." "${RED}"
    distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
    curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
    curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list
    sudo apt update
    sudo apt install -y nvidia-container-toolkit
    sudo systemctl restart docker
    echo_color "NVIDIA Container Toolkit installed." "${GREEN}"
  else
    echo_color "NVIDIA Container Toolkit is installed." "${GREEN}"
  fi
fi

# Test GPU access
echo_color "Testing GPU access for Docker..." "${YELLOW}"
if docker run --rm --gpus all nvidia/cuda:12.9.0-base-ubuntu24.04 nvidia-smi > /dev/null 2>&1; then
  echo_color "✅ GPU is accessible to Docker." "${GREEN}"
  has_gpu_access=true
else
  echo_color "⚠️ Docker cannot access GPU." "${RED}"
  if [ "$is_wsl2" = true ]; then
    echo_color "This is likely because Docker Desktop on Windows is not running" "${YELLOW}"
    echo_color "or does not have WSL2 GPU pass-through enabled." "${YELLOW}"
    echo_color "Please check Docker Desktop settings on Windows." "${YELLOW}"
    
    read -p "Would you like to continue with CPU-only mode? (y/n): " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
      echo_color "Continuing with CPU-only mode." "${YELLOW}"
      has_gpu_access=false
    else
      echo_color "Exiting. Please start Docker Desktop and try again." "${YELLOW}"
      exit 1
    fi
  else
    echo_color "GPU will not be available to FramePack." "${YELLOW}"
    has_gpu_access=false
  fi
fi

# Create outputs directory if it doesn't exist
mkdir -p "$REPO_DIR/outputs"

# Step 2: Check for Docker image
echo_color "\nStep 2: Checking Docker image..." "${YELLOW}"

# Check if Docker image exists
if docker images -q $IMAGE_NAME > /dev/null; then
  echo_color "✅ FramePack Docker image found." "${GREEN}"
else
  echo_color "ℹ️ FramePack Docker image not found. Building..." "${YELLOW}"
  echo_color "Building Docker image (this may take a while)..." "${YELLOW}"
  
  # Check if Dockerfile exists
  if [ ! -f "$REPO_DIR/Dockerfile" ]; then
    echo_color "❌ Dockerfile not found!" "${RED}"
    exit 1
  fi
  
  # Build the Docker image with progress display
  if ! docker build -t $IMAGE_NAME "$REPO_DIR"; then
    echo_color "❌ Failed to build Docker image!" "${RED}"
    exit 1
  fi
  
  echo_color "✅ Docker image built successfully." "${GREEN}"
fi

# Step 3: Manage running containers
echo_color "\nStep 3: Managing containers..." "${YELLOW}"

# Check if the container is already running
if docker ps -q --filter "name=$CONTAINER_NAME" | grep -q .; then
  echo_color "ℹ️ FramePack container is already running." "${YELLOW}"
  
  read -p "Do you want to stop it and start a new container? (y/n): " choice
  if [[ "$choice" =~ ^[Yy]$ ]]; then
    echo_color "Stopping existing container..." "${YELLOW}"
    docker stop $CONTAINER_NAME > /dev/null 2>&1
    docker rm $CONTAINER_NAME > /dev/null 2>&1
  else
    echo_color "Attaching to existing container logs..." "${YELLOW}"
    echo_color "✅ FramePack is already running at: http://localhost:$PORT" "${GREEN}"
    docker logs -f $CONTAINER_NAME
    exit 0
  fi
fi

# Check if port is already in use by something else
if docker ps -q --filter "publish=$PORT" | grep -q .; then
  echo_color "⚠️ Port $PORT is already in use by another container." "${YELLOW}"
  
  # Find container using the port
  OTHER_CONTAINER=$(docker ps --filter "publish=$PORT" --format "{{.Names}}")
  echo_color "Container '$OTHER_CONTAINER' is using port $PORT." "${YELLOW}"
  
  read -p "Stop this container and use port $PORT? (y/n): " choice
  if [[ "$choice" =~ ^[Yy]$ ]]; then
    echo_color "Stopping container..." "${YELLOW}"
    docker stop $OTHER_CONTAINER > /dev/null 2>&1
  else
    # Find an available port
    PORT=7861
    while docker ps -q --filter "publish=$PORT" | grep -q .; do
      PORT=$((PORT + 1))
    done
    echo_color "Using alternative port: $PORT" "${GREEN}"
  fi
fi

# Step 4: Launch container
echo_color "\nStep 4: Launching FramePack..." "${YELLOW}"

# Use GPU if available and requested
if [ "$USE_GPU" = true ]; then
  echo_color "Starting with GPU acceleration..." "${GREEN}"
  
  # GPU container launch command (similar to FaceFusion implementation)
  docker_cmd="docker run -d \
    --gpus all \
    --name $CONTAINER_NAME \
    -e NVIDIA_VISIBLE_DEVICES=all \
    -e NVIDIA_DRIVER_CAPABILITIES=all \
    -p $PORT:7860 \
    -v \"$REPO_DIR/outputs:/app/outputs\" \
    $IMAGE_NAME"
  
  echo_color "Command: $docker_cmd" "${YELLOW}"
  CONTAINER_ID=$(eval $docker_cmd)
  GPU_MODE="GPU"
else
  echo_color "Starting in CPU-only mode (slower performance)..." "${YELLOW}"
  
  # CPU container launch command
  docker_cmd="docker run -d \
    --name $CONTAINER_NAME \
    -p $PORT:7860 \
    -v \"$REPO_DIR/outputs:/app/outputs\" \
    $IMAGE_NAME"
  
  echo_color "Command: $docker_cmd" "${YELLOW}"
  CONTAINER_ID=$(eval $docker_cmd)
  GPU_MODE="CPU"
fi

# Check if container started successfully
if [ -z "$CONTAINER_ID" ] || ! docker ps -q --filter "id=$CONTAINER_ID" | grep -q .; then
  echo_color "\n❌ Failed to start container!" "${RED}"
  
  # Check for logs
  if [ ! -z "$CONTAINER_ID" ]; then
    echo_color "Container logs:" "${YELLOW}"
    docker logs "$CONTAINER_ID"
  fi
  
  exit 1
fi

echo_color "\n✅ Container started successfully" "${GREEN}"

# Step 5: Monitor and display status
echo_color "\nStep 5: Monitoring startup..." "${YELLOW}"

# Wait for container to initialize
echo_color "Waiting for application to start..." "${YELLOW}"

# Display spinner while waiting
SPIN_CHARS="/-\|"
MAX_WAIT=120  # Maximum wait time in seconds
for ((i=0; i<$MAX_WAIT; i++)); do
  SPINNER=${SPIN_CHARS:i%4:1}
  printf "\r${YELLOW}[%s] Initializing...${NC}" "$SPINNER"
  
  # Check if application is ready by looking for Gradio URL in logs
  if docker logs $CONTAINER_NAME 2>&1 | grep -q "Running on local URL:  http://0.0.0.0:7860"; then
    # Application is ready
    clear
    echo_color "╭──────────────────────────────────────────────────────────╮" "${CYAN}"
    echo_color "│                 FRAMEPACK IS READY                     │" "${CYAN}"
    echo_color "╰──────────────────────────────────────────────────────────╯" "${CYAN}"
    echo_color "" ""
    
    if [ "$GPU_MODE" = "GPU" ]; then
      echo_color "💻 Running with GPU acceleration" "${GREEN}"
    else
      echo_color "💻 Running in CPU-only mode (slower performance)" "${YELLOW}"
    fi
    
    echo_color "🌐 Access the web interface at:  http://localhost:$PORT" "${GREEN}"
    echo_color "💾 Generated outputs will be saved to: $REPO_DIR/outputs" "${GREEN}"
    echo_color "📋 Press Ctrl+C at any time to stop the application" "${GREEN}"
    echo_color "" ""
    
    # Attach to container logs
    echo_color "Container logs:" "${YELLOW}"
    docker logs -f $CONTAINER_NAME
    break
  fi
  
  # Check if container has stopped unexpectedly
  if ! docker ps -q --filter "id=$CONTAINER_ID" | grep -q .; then
    echo_color "\n❌ Container stopped unexpectedly!" "${RED}"
    echo_color "Container logs:" "${YELLOW}"
    docker logs $CONTAINER_NAME
    exit 1
  fi
  
  sleep 1
done

# If we reach here without finding the ready message, container might still be starting
if [ $i -eq $MAX_WAIT ]; then
  echo_color "\n⚠️ Application hasn't shown ready message yet" "${YELLOW}"
  echo_color "You can still try accessing it at: http://localhost:$PORT" "${GREEN}"
  echo_color "Latest container logs:" "${YELLOW}"
  docker logs $CONTAINER_NAME | tail -n 20
  
  # Attach to container logs
  echo_color "\nAttaching to container logs..." "${YELLOW}"
  docker logs -f $CONTAINER_NAME
fi

# Clean up on exit
cleanup() {
  echo -e "\n${YELLOW}Cleaning up...${NC}"
  if [ ! -z "$CONTAINER_ID" ]; then
    echo -e "${YELLOW}Stopping container ${CONTAINER_ID}...${NC}"
    docker stop "$CONTAINER_ID" >/dev/null 2>&1
  fi
  exit 0
}

# Register the cleanup function
trap cleanup SIGINT SIGTERM

# Step 4: Launch container with GPU support
echo -e "\n${CYAN}Launching FramePack container...${NC}"

# Stop any existing containers using our name
if docker ps -a --filter "name=$CONTAINER_NAME" | grep -q .; then
  echo -e "${YELLOW}Removing existing container...${NC}"
  docker stop "$CONTAINER_NAME" >/dev/null 2>&1
  docker rm "$CONTAINER_NAME" >/dev/null 2>&1
  sleep 1
fi

# Check if port is in use
if docker ps --filter "publish=$PORT" | grep -q .; then
  echo -e "${YELLOW}Port $PORT is in use by another container.${NC}"
  read -p "Stop that container and use port $PORT? (y/n): " choice
  if [[ "$choice" =~ ^[Yy]$ ]]; then
    CONTAINER_USING_PORT=$(docker ps --filter "publish=$PORT:" --format "{{.ID}}")
    if [ ! -z "$CONTAINER_USING_PORT" ]; then
      docker stop "$CONTAINER_USING_PORT" >/dev/null 2>&1
      sleep 1
    fi
  else
    # Find an available port
    PORT=7861
    while docker ps --filter "publish=$PORT:" | grep -q .; do
      PORT=$((PORT + 1))
    done
    echo -e "${GREEN}Using alternative port: $PORT${NC}"
  fi
fi

# Launch the container with explicit GPU support
echo -e "${GREEN}Starting container with GPU support on port $PORT...${NC}"

# Run the container with GPU support
CONTAINER_ID=$(docker run -d \
  --name "$CONTAINER_NAME" \
  --gpus all \
  -e NVIDIA_VISIBLE_DEVICES=all \
  -e NVIDIA_DRIVER_CAPABILITIES=all \
  -p "$PORT:7860" \
  -v "$REPO_DIR/outputs:/app/outputs" \
  "$IMAGE_NAME")

echo -e "${GREEN}Container started with ID: $CONTAINER_ID${NC}"

# Monitor container startup
echo -e "${YELLOW}Waiting for application to start...${NC}"

# Show spinner while waiting for initialization
spinner=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
spin=0
max_wait=240  # Wait up to 4 minutes (many models to download)

for ((i=0; i<max_wait; i++)); do
  # Check if container is still running
  if ! docker ps -q --filter "id=$CONTAINER_ID" | grep -q .; then
    echo -e "\n${RED}Container stopped unexpectedly!${NC}"
    echo -e "${YELLOW}Container logs:${NC}"
    docker logs "$CONTAINER_ID" | tail -n 20
    echo -e "\n${YELLOW}Run this command to see more logs:${NC}"
    echo -e "docker logs $CONTAINER_ID"
    exit 1
  fi
  
  # Check if application is ready
  if docker logs "$CONTAINER_ID" 2>&1 | grep -q "Running on local URL:  http://0.0.0.0:7860"; then
    clear
    echo -e "${GREEN}╭───────────────────────────────────────────────────────────╮${NC}"
    echo -e "${GREEN}│                  FRAMEPACK IS READY                     │${NC}"
    echo -e "${GREEN}╰───────────────────────────────────────────────────────────╯${NC}"
    echo -e "\n${GREEN}💻 FramePack is running with GPU acceleration${NC}"
    echo -e "${GREEN}🌐 Access it at: http://localhost:$PORT${NC}"
    echo -e "${GREEN}📁 Outputs will be saved to: $REPO_DIR/outputs${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop the container${NC}\n"
    
    # Attach to container logs
    docker logs -f "$CONTAINER_ID"
    break
  fi
  
  # Update spinner
  spin_char="${spinner[$((spin % 10))]}"
  spin=$((spin + 1))
  printf "${YELLOW}%s Initializing... (This may take several minutes for model downloads)${NC}\r" "$spin_char"
  sleep 1
done

# If we get here without success message, check if container is still running
if [ $i -eq $max_wait ] && docker ps -q --filter "id=$CONTAINER_ID" | grep -q .; then
  echo -e "\n${YELLOW}Container is still running but didn't output the ready message yet.${NC}"
  echo -e "${YELLOW}This could be normal if it's downloading models.${NC}"
  echo -e "${GREEN}Try accessing the application at: http://localhost:$PORT${NC}"
  echo -e "${YELLOW}Container logs:${NC}"
  docker logs "$CONTAINER_ID" | tail -n 30
  echo -e "\n${YELLOW}Attaching to container logs:${NC}"
  docker logs -f "$CONTAINER_ID"
fi

# Function to find a free port starting from a base port
find_free_port() {
  local base_port=$1
  local port=$base_port
  
  while check_port_in_use $port; do
    echo_color "Port $port is already in use. Trying another port..." "${YELLOW}"
    port=$((port + 1))
  done
  
  echo "$port"
}

# Function to run container with optimized GPU settings - returns container ID or empty string on failure
run_container() {
  local gpu_mode=$1
  local container_id
  
  # Create a temporary file to capture the docker command output
  local temp_output=$(mktemp)
  
  # Check if port 7860 is in use and handle it
  if check_port_in_use 7860; then
    echo_color "\n⚠️ Port 7860 is already in use" "${YELLOW}"
    
    # Find the container using port 7860
    local existing_container=$(docker ps -q --filter "publish=7860")
    if [ ! -z "$existing_container" ]; then
      echo_color "Container using port 7860: $(docker ps --filter "id=$existing_container" --format "{{.Image}} (running for {{.RunningFor}}")" "${YELLOW}"
      
      # Ask user if they want to stop the existing container
      read -p "Do you want to stop this container and use port 7860? (y/n): " choice
      if [[ "$choice" =~ ^[Yy]$ ]]; then
        echo_color "Stopping container..." "${YELLOW}"
        docker stop "$existing_container" > /dev/null 2>&1
        sleep 2
        PORT=7860
      else
        # Find an alternative port
        PORT=$(find_free_port 7861)
        echo_color "Using alternative port: $PORT" "${GREEN}"
      fi
    fi
  else
    # Port 7860 is free
    PORT=7860
  fi
  
  # First check if any existing framepack containers are running
  existing_containers=$(docker ps -q --filter "ancestor=framepack:latest")
  if [ ! -z "$existing_containers" ]; then
    echo_color "Found existing FramePack containers. Stopping them..." "${YELLOW}"
    docker stop $existing_containers > /dev/null 2>&1
    sleep 2
  fi

  # Always use GPU mode with proper NVIDIA configuration (similar to FaceFusion)
  echo_color "Starting container with full GPU acceleration on port $PORT..." "${YELLOW}"
  
  # Use the optimal GPU configuration for maximum performance
  docker_cmd="docker run -d \
    --gpus all \
    -e NVIDIA_VISIBLE_DEVICES=all \
    -e NVIDIA_DRIVER_CAPABILITIES=all \
    -p $PORT:7860 \
    -v \"$REPO_DIR/outputs:/app/outputs\" \
    --name framepack-gpu \
    framepack:latest"
  
  echo_color "Running: $docker_cmd" "${YELLOW}"
  
  # Execute the docker command
  eval $docker_cmd > "$temp_output" 2>&1
  
  # Get the exit code of the docker run command
  local exit_code=$?
  
  # Show the docker command output for debugging
  echo_color "Docker command output:" "${YELLOW}"
  cat "$temp_output"
  
  # Read the container ID from the temporary file
  container_id=$(cat "$temp_output")
  
  # Clean up the temporary file
  rm "$temp_output"
  
  # Check if the docker run command succeeded
  if [ $exit_code -ne 0 ] || [ -z "$container_id" ] || ! docker ps -q --filter "id=$container_id" | grep -q .; then
    # If we failed, show a detailed error message
    echo_color "Failed to start container" "${RED}"
    
    if [ $exit_code -ne 0 ]; then
      echo_color "Docker exit code: $exit_code" "${RED}"
    fi
    
    if [ -z "$container_id" ]; then
      echo_color "No container ID was returned" "${RED}"
    fi
    
    # Try to get more details about what happened
    if [ ! -z "$container_id" ]; then
      echo_color "Container logs:" "${YELLOW}"
      docker logs "$container_id" 2>&1 | tail -n 10
      echo_color "Container status:" "${YELLOW}"
      docker inspect "$container_id" --format='{{.State.Status}} (ExitCode: {{.State.ExitCode}})'
    fi
    
    return 1
  fi
  
  # Return the container ID
  echo "$container_id"
  return 0
}

# Function to check container status and display splash message
check_container_status() {
  local container_id=$1
  local gpu_mode=$2
  local port=${3:-7860}  # Default to 7860 if not specified
  local max_attempts=60  # Increased to give more time to start
  local attempt=0
  local status
  
  echo_color "Starting FramePack application..." "${YELLOW}"
  
  while [ $attempt -lt $max_attempts ]; do
    # Check if container is still running
    if ! docker ps -q --filter "id=$container_id" | grep -q .; then
      # Container stopped - check exit code
      exit_code=$(docker inspect $container_id --format='{{.State.ExitCode}}' 2>/dev/null)
      if [ "$exit_code" != "0" ]; then
        echo_color "⚠️ FramePack failed to start! (Exit code: $exit_code)" "${RED}"
        echo_color "Container logs:" "${RED}"
        docker logs $container_id | tail -n 20
        return 1
      fi
      break
    fi
    
    # Check logs for the Gradio URL or any initialization message
    if docker logs $container_id 2>&1 | grep -q "Running on local URL:"; then
      clear
      echo_color "✅ FramePack started successfully!" "${GREEN}"
      echo_color "" ""
      echo_color "╭──────────────────────────────────────────────────────────╮" "${YELLOW}"
      echo_color "│                   FRAMEPACK IS READY                    │" "${YELLOW}"
      echo_color "╰──────────────────────────────────────────────────────────╯" "${YELLOW}"
      echo_color "" ""
      if [ "$gpu_mode" = "gpu" ]; then
        echo_color "💻 Running with GPU acceleration" "${GREEN}"
      else
        echo_color "💻 Running in CPU-only mode (slower performance)" "${YELLOW}"
      fi
      echo_color "🌐 Access the web interface at:  http://localhost:$port" "${GREEN}"
      echo_color "💾 Generated outputs will be saved to: $REPO_DIR/outputs" "${GREEN}"
      echo_color "📋 Press Ctrl+C to stop the application" "${GREEN}"
      echo_color "" ""
      return 0
    fi
    
    # Wait a moment before checking again
    sleep 1
    attempt=$((attempt+1))
    
    # Show a spinner
    printf "\r${YELLOW}Starting FramePack%s${NC}" ".$(printf '%0.s.' $(seq 1 $((attempt % 3 + 1))))"
  done
  
  # If we get here and haven't detected success or failure, show a generic message
  if [ $attempt -eq $max_attempts ]; then
    echo_color "\n⚠️ FramePack may be started but we couldn't detect success message." "${YELLOW}"
    echo_color "Try accessing the application at: http://localhost:7860" "${GREEN}"
    echo_color "If it doesn't work, check the logs with: docker logs $container_id" "${GREEN}"
    return 2
  fi
}

# Start the container with appropriate mode
echo_color "\n💻 Launching FramePack..." "${YELLOW}"

# First ensure no previous containers are running
existing_containers=$(docker ps -q --filter "ancestor=framepack:latest")
if [ ! -z "$existing_containers" ]; then
  echo_color "Stopping any existing FramePack containers..." "${YELLOW}"
  docker stop $existing_containers > /dev/null 2>&1
  sleep 2
fi

# Check for Docker Desktop in WSL2
if grep -q "microsoft" /proc/version 2>/dev/null; then
  echo_color "\n💡 Running in WSL2 environment" "${YELLOW}"
  echo_color "Make sure Docker Desktop is running on Windows" "${YELLOW}"
  echo_color "and that GPU passthrough is enabled in Docker Desktop settings" "${YELLOW}"
  
  # Check if nvidia-smi works
  if ! nvidia-smi > /dev/null 2>&1; then
    echo_color "\n❌ Cannot access NVIDIA GPU from WSL2!" "${RED}"
    echo_color "Please make sure:" "${YELLOW}"
    echo_color "1. Docker Desktop is running on Windows" "${YELLOW}"
    echo_color "2. WSL Integration is enabled in Docker Desktop settings" "${YELLOW}"
    echo_color "3. GPU settings are enabled in Docker Desktop Resources > WSL Integration" "${YELLOW}"
    exit 1
  fi
fi

# Start container with GPU support
echo_color "\n🚀 Starting FramePack with GPU acceleration..." "${GREEN}"
container_id=$(run_container "gpu")
use_gpu="gpu"

# Verify the container actually started
if [ -z "$container_id" ]; then
  echo_color "\n❌ Failed to start FramePack with GPU support" "${RED}"
  echo_color "This might be due to:" "${YELLOW}"
  echo_color "- Docker Desktop not running (if using WSL2)" "${YELLOW}"
  echo_color "- Missing NVIDIA drivers or CUDA support" "${YELLOW}"
  echo_color "- GPU not properly accessible to Docker" "${YELLOW}"
  echo_color "\nTry running: nvidia-smi" "${YELLOW}"
  exit 1
fi

echo_color "\n💻 Container started with ID: $container_id" "${GREEN}"

# Wait for the container to initialize and start the application
echo_color "Waiting for GPU initialization..." "${YELLOW}"
sleep 5

# Make sure container is still running
if ! docker ps -q --filter "id=$container_id" | grep -q .; then
  echo_color "\n❌ Container stopped unexpectedly" "${RED}"
  echo_color "Container logs:" "${YELLOW}"
  docker logs "$container_id" | tail -n 20
  exit 1
fi

# Check container status and display splash message
echo_color "Container is running, monitoring startup..." "${GREEN}"
check_container_status "$container_id" "$use_gpu" "$PORT"
status_code=$?

# If the check function returns non-zero, show appropriate message
if [ $status_code -ne 0 ]; then
  echo_color "If you need more detailed logs, run:" "${YELLOW}"
  echo_color "docker logs $container_id" "${GREEN}"
fi

# Attach to container logs (this will keep the script running)
docker logs -f "$container_id"

exit 0
