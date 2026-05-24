---
name: wsl-windows-path-compat
description: Use when an agent running in WSL/Linux cannot read Windows file paths, screenshots, images, Telegram attachments, or file URLs such as C:\Users\...\image.png or file:///C:/... . Converts Windows paths to /mnt/<drive>/ paths, adds runner prompt hints, and verifies the converted path reaches Claude Code, Codex, Hermes, or tg-agent-gateway workers.
metadata:
  short-description: Fix Windows screenshot paths for WSL agents
---

# WSL Windows Path Compatibility

Use this skill when a task fails because an agent running inside WSL/Linux says it cannot directly read a Windows path, especially for screenshots and images passed through Telegram or prompts.

## Trigger Examples

- "Claude Code + DeepSeek 无法读取 Windows 路径截图"
- "agent 看不到 C:\Users\...\Screenshots\xxx.png"
- "Telegram 里发了 Windows 截图路径，worker 读不到"
- "file:///C:/Users/.../image.png 在 WSL 里打不开"

## Core Rule

Do not pass Windows paths to a WSL/Linux runner as the only usable path. Convert them to WSL mount paths and make the converted path explicit in the task prompt or runner input.

Examples:

```text
C:\Users\zhanxp\Pictures\issue.png
-> /mnt/c/Users/zhanxp/Pictures/issue.png

file:///D:/Screenshots/screen%202024-05-24.jpg
-> /mnt/d/Screenshots/screen 2024-05-24.jpg
```

## Conversion Rules

1. Strip a leading `file:///` scheme.
2. Decode URL escapes such as `%20`.
3. Match drive-letter paths: `<letter>:\...` or `<letter>:/...`.
4. Lowercase the drive letter.
5. Replace backslashes with forward slashes.
6. Prefix with `/mnt/<drive>/`.
7. Check existence with the converted path when possible.

Supported image extensions should include at least:

```text
png, jpg, jpeg, webp, bmp, gif, tif, tiff
```

## tg-agent-gateway Workflow

When working in `tg-agent-gateway`, prefer a small prompt-normalization layer before runner execution.

Recommended location:

```text
TaskManager.executeTask()
  -> before buildExecutionPrompt(...)
  -> append Windows path compatibility hint
```

The hint should say:

```text
用户任务中包含 Windows 截图/图片路径。当前 worker 在 WSL/Linux 中执行，读取文件时请优先使用转换后的 WSL 路径：
- C:\Users\...\issue.png -> /mnt/c/Users/.../issue.png (已确认存在/未确认存在)
不要因为原始 Windows 路径不可直接读取而放弃；先尝试对应的 /mnt/<drive>/ 路径。
```

Keep the original user prompt intact. Add the hint after it.

## Verification Checklist

- Unit test pure conversion:
  - `C:\Users\...\x.png` becomes `/mnt/c/Users/.../x.png`
  - `file:///D:/Screenshots/x%201.jpg` becomes `/mnt/d/Screenshots/x 1.jpg`
- Unit test prompt integration:
  - runner input contains the compatibility hint
  - runner input contains the converted `/mnt/<drive>/...` path
- Run the relevant TypeScript checks:

```bash
npm run test:unit -- tests/unit/<path-hint-test>.test.ts
npm run type-check
npm run build
```

- If testing manually through Telegram, send a task with a Windows screenshot path and inspect the run log or mocked runner input for the converted path.

## Failure Patterns

- Model says it cannot access `C:\...` and no `/mnt/c/...` fallback was provided.
- Code only normalizes display text, but the runner receives the original path.
- The conversion happens after the prompt is wrapped, making the hint hard to find or omitted from read-only/reviewer tasks.
- The path regex stops at spaces in filenames.
- URL-encoded paths are not decoded before existence checks.

## Report Guidance

When reporting the fix, include:

```text
Changed Files
- path conversion helper
- runner/task prompt integration
- conversion and integration tests

Verification
- unit tests
- type-check
- build

Remaining Risk
- uncommon file types or paths without extensions may still need manual /mnt/... paths
```
