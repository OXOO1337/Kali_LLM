# Contributing to Kali LLM Installer

Thanks for your interest in improving this project! Contributions of all kinds are welcome — bug reports, fixes, new features, and documentation.

## 🐛 Reporting Bugs

Open an [issue](https://github.com/OXOO1337/Kali_LLM/issues) and include:

- **Kali version** — output of `cat /etc/os-release | grep VERSION`
- **GPU** — output of `nvidia-smi` (or state "CPU only")
- **The menu option** you ran (e.g. `[3] → [3] Custom Hugging Face`)
- **What happened vs. what you expected**
- **Relevant logs** — `/var/log/kali_llm_install.log`, and for services `journalctl -u kali-mcp-api.service -e`
- For **MCP tool failures**, also include `dpkg -s mcp-kali-server | grep -i version`

## 💡 Suggesting Features

Open an issue describing the use case and the behavior you'd like. Keep the project's scope in mind: a local, offline LLM + MCP toolchain for Kali.

## 🔧 Pull Requests

1. Fork the repo and create a branch: `git checkout -b fix/short-description`
2. Make your change and keep the existing style (see below).
3. **Test on a real Kali system** — this script installs packages, writes systemd units, and manages services; it cannot be meaningfully tested on other platforms.
4. Run static checks before submitting:
   ```bash
   bash -n Kali_LLM.sh        # syntax check (must pass)
   shellcheck Kali_LLM.sh     # linting (sudo apt install shellcheck)
   ```
5. Open the PR against `main` with a clear description of what changed and why.

## 🎨 Code Style

- **Bash**, targeting Kali's default shell environment. Keep `#!/bin/bash` and `set -o pipefail`.
- Use the existing helper functions: `print_info`, `print_success`, `print_warn`, `print_error`, `print_step`, and `read_input`.
- **Validate and sanitize all user input** — reuse `sanitize_input` and the allow-list validators (e.g. `valid_model_ref`). Never interpolate raw input into an `su -c` string.
- Use `local` for function variables.
- Keep files **LF line endings, UTF-8, no BOM** (a CRLF shebang breaks execution on Linux).
- Prefer the phased structure (`# PHASE N: ...`) and keep the banner/menu layout consistent.

## 🩹 The MCP Server Patch

Maintenance `[6] → [3]` (`repair_mcp_server`) patches Kali's `mcp-kali-server` (`/usr/share/mcp-kali-server/server.py`) to fix a broken `remove-shell-true` patch that makes every tool endpoint return HTTP 500. It targets specific package versions (see the README's *MCP Server Repair* section). If you touch this function:

- Keep it **idempotent** (guard on the `Patched by Kali_LLM installer` marker) and always keep the `.bak`.
- Match the buggy code with **exact string replacement**, and abort + restore if the patterns don't match (upstream/Kali may fix it, in which case leave the file untouched).
- Always `compile()`-check the result before writing it back.
- If Kali ships a new package version, verify the patterns against it before widening the match.

## 🧩 HF model templates & tool engines

`hf_write_template` decides how an imported GGUF gets tool-calling. Two mechanisms exist and must not be mixed:

- **Older families** (Qwen2.5, Llama 3.x): a Go `TEMPLATE` containing `.Tools` (`chatml` / `llama3` cases).
- **Modern archs** (Qwen3.5, DeepSeek, GLM, Gemma4): Ollama's compiled-in engine via `RENDERER <name>` + `PARSER <name>` (the `renderer:<name>` mode) — **no** custom `TEMPLATE`, and needs Ollama ≥ 0.17.1. Importing a raw GGUF does not auto-apply these ([ollama/ollama#17636](https://github.com/ollama/ollama/issues/17636)).

When adding a new preset, pick the right mechanism for its family; never write a `TEMPLATE` alongside a `RENDERER`/`PARSER`.

## 🔒 Security

This project lets an LLM execute real security tools. When contributing:

- Never expose the MCP Flask API beyond `127.0.0.1`.
- Don't add features that weaken input validation or run untrusted input as commands.
- The MCP patch must always run subprocesses with `shell=False`; never reintroduce `shell=True`.
- Report security-sensitive issues privately to the maintainer rather than in a public issue.

## 📜 License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
