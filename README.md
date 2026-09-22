# 🦾 Kali LLM Installer

> **Enterprise-grade Local LLM + MCP Installer for Kali Linux**
> Run and manage local LLMs entirely on Kali Linux — fully offline, no cloud services.

<p align="center">
  <img src="img/Kali_LLM.png" alt="Kali LLM Installer — Main Menu" width="700">
  <br><em>The script's main interface (live status dashboard + menu)</em>
</p>

<p align="center">
  <img alt="Version" src="https://img.shields.io/badge/version-V1.0-blue">
  <img alt="Platform" src="https://img.shields.io/badge/platform-Kali%20Linux-557C94?logo=kalilinux&logoColor=white">
  <img alt="Shell" src="https://img.shields.io/badge/shell-Bash-4EAA25?logo=gnubash&logoColor=white">
  <img alt="GPU" src="https://img.shields.io/badge/GPU-NVIDIA%20CUDA-76B900?logo=nvidia&logoColor=white">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-green">
</p>

---

## 📖 Overview

An interactive Bash script that automates the setup of a **fully local AI environment** on Kali Linux,
where natural language replaces manual command input — all processing happens on your own hardware,
with no reliance on any third-party service.

The script brings together:

| Component | Role |
|---|---|
| **[Ollama](https://ollama.com/)** | Runs LLMs locally (a wrapper around `llama.cpp`) |
| **[5ire](https://github.com/nanbingxyz/5ire)** | GUI + MCP Client |
| **[mcp-kali-server](https://www.kali.org/tools/mcp-kali-server/)** | MCP server bridging the model to Kali security tools |
| **NVIDIA CUDA** | GPU-accelerated inference |

> Based on the official guide: [Kali & LLM: Completely local with Ollama & 5ire](https://www.kali.org/blog/kali-llm-ollama-5ire/), with an isolated `/srv` layout plus simplified service and update management.

---

## ✨ Features

- 🎛️ **Interactive menu** with a live status dashboard (OS, RAM, GPU, service status, storage usage).
- 🗂️ **Isolated `/srv` layout** — models and binaries kept away from the base filesystem.
- 📦 **Full model management** — pull from the Ollama library, or build GGUF models from Hugging Face via a submenu: one-click **Qwen3.5-4B / 9B presets**, a **quantization chooser** (Q4_K_M → BF16), a **template / tool-engine selector** (Auto · ChatML · Llama 3 · **built-in RENDERER/PARSER** for modern archs like Qwen3.5), and automatic `mmproj` vision-projector detection.
- 🧰 **Maintenance menu** — one place for updates, service control, and the MCP repair.
- 🩹 **MCP server repair** — auto-fixes a bug in the Kali `mcp-kali-server` package that breaks every tool endpoint (see [MCP Server Repair](#-mcp-server-repair)).
- 🛡️ **Safe input** — sanitization and strict allow-lists to prevent command injection.
- 🖥️ **NVIDIA GPU support** — detects the card and installs the proprietary (CUDA) drivers.
- 🧩 **5ire integration** — a smart launcher that auto-starts Ollama + a Kali desktop menu entry.

---

## 📋 Requirements

- **OS**: Kali Linux (Rolling).
- **Privileges**: must be run as `root` (via `sudo`).
- **Recommended hardware**: an NVIDIA card with **6 GB VRAM** or more (CPU works but is slow).
- **Disk**: several GB free on `/srv` (depending on model sizes).
- **Internet**: required to download binaries and models.

---

## 🚀 Installation & Usage

```bash
git clone https://github.com/OXOO1337/Kali_LLM.git
cd Kali_LLM
chmod +x Kali_LLM.sh
sudo ./Kali_LLM.sh
```

> The script must be run as `root`. It automatically checks dependencies and installs any that are missing.

---

## 🧭 Main Menu

```
[1] Prepare Workspace (/srv)                 Create working directories
[2] Install Ollama                           Install Ollama
[3] Download & Manage Models                 Download and manage models
[4] Install 5ire Application                 Install the 5ire GUI
[5] Install & Configure MCP Server           Install the MCP server + Kali tools
[6] Maintenance (Update · Services · Repair) Submenu (see below)
[0] Exit Script                              Quit
```

**`[6] Maintenance` submenu:**

```
[1] Update Tools (System + Ollama + 5ire)    Update all components
[2] Manage Services (MCP API + Ollama)       Start/stop/restart + logs
[3] Repair MCP Server (fix tool endpoints)   Patch the Kali package bug (see below)
[0] Back to Main Menu
```

### Recommended first-run order
`[1]` → `[2]` → `[3]` (pick a model) → `[4]` → `[5]` → then connect MCP inside 5ire.

---

## 🤖 Model Management

<p align="center">
  <img src="img/MODEL%20MANAGEMENT.png" alt="Model Management Menu" width="650">
  <br><em>The model management interface (download / list / remove)</em>
</p>

Option `[3]` supports:

1. **Pull from the Ollama library** (recommended) — Tools-capable models:
   - `qwen2.5:7b`, `qwen2.5:3b`, `mistral-nemo`
   - `llama3.1:8b`, `llama3.2:3b`, `qwen3:4b` *(from the official guide)*
2. **Build from Hugging Face (GGUF)** — opens a submenu of one-click, tool-capable presets (built-in RENDERER/PARSER) plus a custom builder:
   - `[1] Qwen3.5-4B` — `unsloth/Qwen3.5-4B-GGUF` · engine `qwen3.5` · ~6 GB VRAM · Ollama ≥ 0.17.1
   - `[2] Qwen3.5-9B` — `unsloth/Qwen3.5-9B-GGUF` · engine `qwen3.5` · 8 GB+ VRAM · Ollama ≥ 0.17.1
   - `[3] Ornith-1.0-9B` — `ornith-ai/Ornith-1.0-9B-GGUF` · engine `ornith` · 8 GB+ VRAM · Ollama ≥ 0.30.11
   - `[4] LFM2.5-8B-A1B` — `unsloth/LFM2.5-8B-A1B-GGUF` · MoE · engine `lfm2` / parser `lfm2-thinking` · Ollama ≥ 0.30.0
   - `[5] Custom` — enter any `repo`, `filename.gguf`, and model name, pick a template/engine, with automatic `mmproj` vision-projector detection

   The presets and custom builds both let you choose:
   - **Quantization** — `Q4_K_M` (default) · `Q5_K_M` · `Q6_K` · `Q8_0` · `Q3_K_M` · `BF16`
   - **Template / tool engine**:
     - `[1] Auto` — Ollama picks from the GGUF (chat; tools only if embedded)
     - `[2] ChatML` — tool-capable, for **older** families (Qwen2.5 / Qwen3 ChatML GGUFs)
     - `[3] Llama 3` — tool-capable (Llama 3.1 / 3.2)
     - `[4] None` — text-only
     - `[5] Built-in RENDERER/PARSER` — for **modern** archs (Qwen3.5, DeepSeek, GLM, Gemma4…); prompts for the name (e.g. `qwen3.5`). Needs Ollama ≥ 0.17.1.

   > ⚠️ **Tool-calling depends on the runtime, not just the model.** See [How tool-calling works](#-how-tool-calling-works-important) below. For **Qwen3.5** choose option `[5]` and enter `qwen3.5` (the Qwen3.5 presets do this automatically).
3. **List installed models** + disk usage.
4. **Remove a model**.

### 🧠 How tool-calling works (important)

Ollama exposes tools to 5ire in one of two ways — it does **not** use the GGUF's Jinja template for this:

| Model family | What to pick | Why |
|---|---|---|
| **Qwen2.5, Llama 3.1/3.2** (older) | `ChatML` / `Llama 3` | Ollama reads a Go **TEMPLATE** containing `.Tools` |
| **Qwen3.5, Ornith, LFM2.5, DeepSeek, GLM** (modern) | **`[5]` Built-in RENDERER/PARSER** | Tool rendering + parsing are compiled **into Ollama** (a `RENDERER`/`PARSER` pair), not a template |

Importing a raw GGUF does **not** auto-apply the built-in renderer/parser ([ollama/ollama#17636](https://github.com/ollama/ollama/issues/17636)) — the model may even show `tools` in `ollama show` yet still fail to call them (Ollama can't parse the reply back). The script fixes this by writing `RENDERER <name>` + `PARSER <name>` into the Modelfile. The renderer and parser names are family-specific and **can differ** (e.g. LFM2.5 = renderer `lfm2`, parser `lfm2-thinking`); the custom builder asks for both. Verify with `ollama show <model>` (a working import shows a `requires <ver>` line) and by watching the MCP log for `POST /api/tools/... 200`.

---

## 🔌 Connecting MCP to 5ire

<p align="center">
  <img src="img/mcp-kali-server.png" alt="MCP Kali Server connected successfully in 5ire" width="650">
  <br><em>mcp-kali-server connected successfully in 5ire (tools · resources · prompts)</em>
</p>

After running option `[5]`, open 5ire, then go to **Tools → Local** and add a new server:

| Field | Value |
|---|---|
| **Name** | `mcp-kali-server` |
| **Description** | `MCP Kali Server` |
| **Approval Policy** | Your choice |
| **Command** | `/usr/bin/mcp-server` |

Then enable the server (the toggle must turn green). To configure the model: **Workspace → Providers → Ollama**, enable the model with both **Tools** and **Enabled** toggled on.

---

## 🧪 Example

### 1) Chat test

<p align="center">
  <img src="img/Hello%20world.png" alt="Basic chat test in 5ire with a local model" width="700">
  <br><em>Sending a message in chat (Hello world!) to confirm the local model works via Ollama</em>
</p>

### 2) LLM-driven scan (via MCP)

<p align="center">
  <img src="img/scan.png" alt="LLM-driven Nmap scan results through MCP" width="700">
  <br><em>Port-scan results produced by the model using the nmap tool through MCP</em>
</p>

Once the setup is complete, you can ask the model in natural language:

> *Can you please do a port scan on `scanme.nmap.org`, looking for TCP 80,443,21,22?*

The model invokes the `nmap` tool via MCP and returns the results — **all locally**.

---

## ⚙️ Service Management (Maintenance `[6] → [2]`)

| Command | Function |
|---|---|
| Start / Stop / Restart MCP API | Control the `kali-mcp-api.service` (port 5000) |
| MCP API logs | Last 30 lines from `journalctl` |
| Start / Stop Ollama | Control the Ollama server (port 11434) |

---

## 🩹 MCP Server Repair

Run from **Maintenance `[6] → [3]`** (also applied automatically during install `[5]` and re-applied after updates).

Kali's `mcp-kali-server` package ships a broken `remove-shell-true` patch that **breaks every tool endpoint** (`/api/tools/nmap`, `dirb`, `gobuster`, ...). This is why the chat works but **tool-calling fails**.

**Root cause** (verified against the [Kali package](https://gitlab.com/kalilinux/packages/mcp-kali-server) and [upstream](https://github.com/Wh0am123/MCP-Kali-Server)):

1. The patch adds a guard that **rejects non-string commands** (`raise ValueError("CommandExecutor expects a string...")`). But the tool endpoints build the command as an **argv list**, so every one of them returns **HTTP 500**.
2. It computes `cmd_args = shlex.split(...)` but never uses it — `subprocess.Popen` still runs with `self.command` and `shell=self.use_shell`, so `shell=True` remains active (the patch's own security goal fails).

**Affected package versions** (Kali 2026.x):

| Version | Date | Note |
|---|---|---|
| `0.0~git20260119.bffe9f2-0kali3` | 2026-03-12 | Bug introduced (`shell=False` patch) |
| `0.0~git20260317.00154c0-0kali1` | 2026-03-18 | Patch refreshed (verified buggy) |
| `0.0~git20260317.00154c0-0kali2` | 2026-08-25 | "Fix the patch" ([bug #9610](https://bugs.kali.org/view.php?id=9610)) — still ships the broken hunk on `kali/master` |

Check your installed version with:
```bash
dpkg -s mcp-kali-server | grep -i version
```

**What the repair does**: rewrites `CommandExecutor.execute()` in `/usr/share/mcp-kali-server/server.py` to accept both a string (via `shlex.split`) and an argv list, and to always run with `shell=False`. It is **idempotent**, keeps a `.bak`, validates the result with `python -c compile` before writing, and restores the backup on any failure.

> The patch is applied automatically during install (option `[5]`) and re-applied after upgrades (Maintenance `[6] → [1]`), since `server.py` is not a dpkg conffile and gets overwritten by package updates. Run Maintenance `[6] → [3]` manually anytime tool endpoints return 500.

---

## 🗂️ Paths & Layout

| Path | Purpose |
|---|---|
| `/srv/ollama_bin` | Ollama binaries |
| `/srv/ollama_models` | Model storage (`OLLAMA_MODELS`) |
| `/srv/models_temp` | Temporary GGUF files during builds |
| `/opt/5ire/5ire.AppImage` | The 5ire application |
| `/usr/local/bin/5ire` | Smart launcher (starts Ollama, then 5ire) |
| `/etc/systemd/system/kali-mcp-api.service` | Flask API service for MCP |
| `/usr/share/mcp-kali-server/server.py` | MCP Flask backend (patched by Maintenance `[6] → [3]`; `.bak` kept) |
| `/var/log/kali_llm_install.log` | Installation log |

---

## 🛠️ Troubleshooting

- **MCP API fails to start**: `journalctl -u kali-mcp-api.service -e`
- **Ollama not responding**: check `/tmp/ollama.log`, or restart it from Maintenance `[6] → [2]`.
- **NVIDIA drivers**: reboot after installation, then verify with `nvidia-smi`.
- **5ire won't launch**: the launcher uses `--appimage-extract-and-run`; ensure `libfuse2t64` is installed.
- **Chat works but tool-calling / MCP does nothing** — two possible causes:
  1. **Server side**: the Kali `mcp-kali-server` package bug (tool endpoints return HTTP 500). Run **Maintenance `[6] → [3]` Repair MCP Server** — see [MCP Server Repair](#-mcp-server-repair).
  2. **Model side** (HF GGUF models): the model was imported without a working tool engine. For **Qwen3.5 and other modern archs**, re-import via `[3] → [2]` and pick template **`[5]` Built-in RENDERER/PARSER** (enter `qwen3.5`); for older families pick `ChatML` / `Llama 3`. Then verify: `ollama show <model>` lists `tools` (a Qwen3.5 import also shows `requires 0.17.1`), and the MCP log shows `POST /api/tools/... 200`. See [How tool-calling works](#-how-tool-calling-works-important).

---

## 🔒 Security Notes

- The `kali-server-mcp` backend is a **Flask development server with no authentication**. It listens on **`127.0.0.1` (localhost) only** and must **not** be exposed to a network. Do not port-forward or bind port `5000` to a public interface.
- This setup grants the LLM the ability to **execute real Kali security tools** (nmap, hydra, metasploit, sqlmap, ...) via natural language. Run it only on a host you control and trust.
- Review the MCP tool "Approval Policy" in 5ire — set it to prompt for confirmation if you want a human in the loop before commands run.

## ⚠️ Disclaimer

These tools are intended for **authorized security testing and education only**.
Using them against systems you do not have explicit permission to test is **illegal**. You are solely responsible for your actions.

---

## 👤 Developer

**0X001337** — Version **V1.0**

## 📜 License

MIT License.
