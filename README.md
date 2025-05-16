# FramePack Docker Launcher

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Docker Pulls](https://img.shields.io/docker/pulls/yassineboumiza/framepack-gpu)](https://hub.docker.com/r/yassineboumiza/framepack-gpu)

A Docker-based launcher for [FramePack](https://github.com/lllyasviel/FramePack), making it easy to run FramePack with GPU acceleration. This project is maintained by [Yassine Boumiza](https://github.com/yassineboumiza).

## 📝 About FramePack

FramePack is an open-source project by [lllyasviel](https://github.com/lllyasviel) that enables practical video diffusion models. It allows for generating and editing videos using AI models with GPU acceleration.

**All credit for the core FramePack technology goes to the original authors.** This project simply packages it in an easy-to-use Docker container.

## 🚀 Features

- 🐳 Easy Docker-based deployment
- 🎮 Full GPU acceleration support
- 🔄 Automatic model downloading
- 📁 Persistent output storage
- 🔧 Simple configuration

## 🛠 Prerequisites

- Linux (tested on Ubuntu 22.04)
- [Docker](https://docs.docker.com/engine/install/) (with NVIDIA Container Toolkit)
- NVIDIA GPU with drivers installed
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)

## 🏗 Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/yassineboumiza/framepack-docker.git
   cd framepack-docker
   ```

2. Make the launcher script executable:
   ```bash
   chmod +x framepack.sh
   ```

## 🚀 Usage

### Starting FramePack

```bash
./framepack.sh
```

The first run will:
1. Build the Docker image (takes a while)
2. Download required AI models (can take 30-60 minutes)
3. Start the FramePack web interface

Once started, access the web interface at: http://localhost:7860

### Stopping FramePack

Press `Ctrl+C` in the terminal where you ran `./framepack.sh` to stop the container.

### Outputs

All generated videos and images are saved to the `outputs` directory, which persists between container restarts.

## 🔧 Configuration

You can modify the following environment variables in `framepack.sh`:

```bash
IMAGE_NAME="framepack:latest"  # Docker image name
CONTAINER_NAME="framepack-gpu"  # Container name
PORT=7860  # Web interface port
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Huge thanks to [lllyasviel](https://github.com/lllyasviel) and all [FramePack contributors](https://github.com/lllyasviel/FramePack/graphs/contributors) for their amazing work.
- This Docker implementation was created by [Yassine Boumiza](https://github.com/yassineboumiza).

## 📄 Related Projects

- [Original FramePack Repository](https://github.com/lllyasviel/FramePack)
- [FramePack Paper](https://arxiv.org/abs/2306.xxxxx) (when available)

## 📧 Contact

For questions or support, please open an issue on GitHub or contact [Yassine Boumiza](mailto:yassine.boumiza@example.com).

---

Made with ❤️ by [Yassine Boumiza](https://github.com/yassineboumiza)
