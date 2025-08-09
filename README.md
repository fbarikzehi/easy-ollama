# 🦙 Easy Ollama

A modern, user-friendly shell script to **install, update, and manage Ollama** on your local machine.  
Designed for developers who want a quick, interactive way to set up Ollama and its models — without digging through docs.
 

## ✨ Features

- **✅ Automatic Installation** — Installs Ollama if it's missing, with OS detection.
- **✅ Update Checker** — Detects newer versions and prompts before updating.
- **✅ System Resource Detection** — Reads CPU, RAM, and GPU details to suggest compatible models.
- **✅ Model Management**  
  - Lists all available Ollama models  
  - Marks installed models with `[INSTALLED]`  
  - Allows interactive model installation
- **✅ Model Switcher** — Easily switch between installed models.
- **Preferences** — Saves your favorite models in a config file.
- **Automatic Recommendations** — Suggests models based on your system specs (RAM/GPU VRAM).
- **TUI Mode** — Optional `fzf` or `dialog` UI for model selection.
- **Docker Fallback** — Runs Ollama in Docker if native install isn’t supported.
- **What else do you want?**
 

## 📦 Requirements

- **OS**
- **Bash**
- **Dependencies**:
  - `curl` — for downloading Ollama
  - `nvidia-smi` — if using NVIDIA GPU (optional)
 

## 🚀 Quick Start

```bash
# Clone the repo
git clone https://github.com/fbarikzehi/easy-ollama.git
cd easy-ollama
```
# Make script executable

```bash
chmod +x setup.sh
```
# Run it

```bash
./setup.sh
```
 

## 📜 License

MIT License. See LICENSE for details.
 

## ❤️ Contributing

Pull requests welcome! If you have a favorite model or improvement idea, open an issue or PR.
