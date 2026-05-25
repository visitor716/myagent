#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
CDP_ENDPOINT="${BOTFATHER_CDP_ENDPOINT:-http://127.0.0.1:9222}"
PLAYWRIGHT_NODE_PATH="${PLAYWRIGHT_NODE_PATH:-/home/zhanxp/.nvm/versions/node/v20.20.2/lib/node_modules/@playwright/cli/node_modules}"
TARGET_USERNAME="${TARGET_BOT_USERNAME:-}"
TARGET_USERNAME_FILE="${TARGET_BOT_USERNAME_FILE:-}"
ACTIVE_USERNAME="${ACTIVE_BOT_USERNAME:-}"
ACTIVE_USERNAME_FILE="${ACTIVE_BOT_USERNAME_FILE:-}"
DISPLAY_NAME="${BOT_DISPLAY_NAME:-}"
CONFIRM_DELETE=false
MAX_PAGES="${BOTFATHER_MAX_PAGES:-8}"

usage() {
  cat <<USAGE
Usage:
  $SCRIPT_NAME --dry-run
  $SCRIPT_NAME --confirm-delete

Environment or flags:
  TARGET_BOT_USERNAME          BotFather username to delete, for example @old_bot
  TARGET_BOT_USERNAME_FILE     File containing the target username; preferred for sensitive names
  ACTIVE_BOT_USERNAME          Known-good bot that must remain present, for example @current_bot
  ACTIVE_BOT_USERNAME_FILE     File containing the active username
  BOT_DISPLAY_NAME             Optional display name expected in delete prompts
  BOTFATHER_CDP_ENDPOINT       CDP endpoint, default http://127.0.0.1:9222
  PLAYWRIGHT_NODE_PATH         Node module path containing playwright
  BOTFATHER_MAX_PAGES          Max /mybots pages to scan, default 8

Flags:
  --target-username <name>
  --target-username-file <path>
  --active-username <name>
  --active-username-file <path>
  --display-name <name>
  --cdp-endpoint <url>
  --max-pages <n>
  --dry-run
  --confirm-delete
  -h, --help

The script masks target and active usernames in output. It never prints tokens.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-username)
      TARGET_USERNAME="${2:-}"
      shift 2
      ;;
    --target-username-file)
      TARGET_USERNAME_FILE="${2:-}"
      shift 2
      ;;
    --active-username)
      ACTIVE_USERNAME="${2:-}"
      shift 2
      ;;
    --active-username-file)
      ACTIVE_USERNAME_FILE="${2:-}"
      shift 2
      ;;
    --display-name)
      DISPLAY_NAME="${2:-}"
      shift 2
      ;;
    --cdp-endpoint)
      CDP_ENDPOINT="${2:-}"
      shift 2
      ;;
    --max-pages)
      MAX_PAGES="${2:-}"
      shift 2
      ;;
    --dry-run)
      CONFIRM_DELETE=false
      shift
      ;;
    --confirm-delete)
      CONFIRM_DELETE=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -n "$TARGET_USERNAME_FILE" ]]; then
  TARGET_USERNAME="$(<"$TARGET_USERNAME_FILE")"
fi
if [[ -n "$ACTIVE_USERNAME_FILE" ]]; then
  ACTIVE_USERNAME="$(<"$ACTIVE_USERNAME_FILE")"
fi

TARGET_USERNAME="$(printf '%s' "$TARGET_USERNAME" | tr -d '\r\n' | xargs)"
ACTIVE_USERNAME="$(printf '%s' "$ACTIVE_USERNAME" | tr -d '\r\n' | xargs)"
DISPLAY_NAME="$(printf '%s' "$DISPLAY_NAME" | tr -d '\r\n')"

if [[ -z "$TARGET_USERNAME" || "$TARGET_USERNAME" != @* ]]; then
  echo "TARGET_BOT_USERNAME must be set and must start with @." >&2
  exit 2
fi
if [[ -n "$ACTIVE_USERNAME" && "$ACTIVE_USERNAME" != @* ]]; then
  echo "ACTIVE_BOT_USERNAME must start with @ when provided." >&2
  exit 2
fi
if [[ -n "$ACTIVE_USERNAME" && "$TARGET_USERNAME" == "$ACTIVE_USERNAME" ]]; then
  echo "Refusing to delete because target and active bot are the same." >&2
  exit 2
fi
if ! [[ "$MAX_PAGES" =~ ^[0-9]+$ ]] || [[ "$MAX_PAGES" -lt 1 ]]; then
  echo "BOTFATHER_MAX_PAGES must be a positive integer." >&2
  exit 2
fi

export TARGET_BOT_USERNAME="$TARGET_USERNAME"
export ACTIVE_BOT_USERNAME="$ACTIVE_USERNAME"
export BOT_DISPLAY_NAME="$DISPLAY_NAME"
export BOTFATHER_CDP_ENDPOINT="$CDP_ENDPOINT"
export BOTFATHER_CONFIRM_DELETE="$CONFIRM_DELETE"
export BOTFATHER_MAX_PAGES="$MAX_PAGES"
export NODE_PATH="$PLAYWRIGHT_NODE_PATH${NODE_PATH:+:$NODE_PATH}"

node <<'NODE'
const { chromium } = require('playwright');

const target = process.env.TARGET_BOT_USERNAME || '';
const active = process.env.ACTIVE_BOT_USERNAME || '';
const displayName = process.env.BOT_DISPLAY_NAME || '';
const cdpEndpoint = process.env.BOTFATHER_CDP_ENDPOINT || 'http://127.0.0.1:9222';
const confirmDelete = process.env.BOTFATHER_CONFIRM_DELETE === 'true';
const maxPages = Number(process.env.BOTFATHER_MAX_PAGES || '8');

function mask(value) {
  return String(value || '')
    .replaceAll(target, '[TARGET]')
    .replaceAll(active, '[ACTIVE]');
}

function safeJson(value) {
  return JSON.stringify(JSON.parse(JSON.stringify(value, (_key, val) => {
    return typeof val === 'string' ? mask(val) : val;
  })), null, 2);
}

function assertSafe(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

async function wait(ms) {
  await new Promise((resolve) => setTimeout(resolve, ms));
}

async function activeChatState(page) {
  return await page.evaluate(() => {
    const chat = document.querySelector('.chat.active') || document.querySelector('.chat');
    if (!chat) {
      return { ok: false, reason: 'active chat not found' };
    }
    const bubbleElements = Array.from(chat.querySelectorAll('.bubble'));
    const latestBubble = bubbleElements.at(-1) || null;
    const latestText = latestBubble ? (latestBubble.textContent || '').trim() : '';
    const latestButtons = latestBubble
      ? Array.from(latestBubble.querySelectorAll('.reply-markup-button')).map((el) => (el.textContent || '').trim()).filter(Boolean)
      : [];
    const allButtons = Array.from(chat.querySelectorAll('.reply-markup-button')).map((el) => (el.textContent || '').trim()).filter(Boolean);
    return {
      ok: true,
      url: location.href,
      title: document.title,
      chatTextPrefix: (chat.textContent || '').trim().slice(0, 240),
      latestText,
      latestButtons,
      allButtons,
    };
  });
}

async function focusBotFather(page) {
  await page.bringToFront();
  let state = await activeChatState(page);
  if (state.ok && state.chatTextPrefix.includes('BotFather')) {
    return;
  }

  const rect = await page.evaluate(() => {
    const rows = Array.from(document.querySelectorAll('.chatlist-chat'));
    const row = rows.find((candidate) => {
      const titles = Array.from(candidate.querySelectorAll('.peer-title,.user-title')).map((el) => (el.textContent || '').trim());
      return titles.includes('BotFather') || (candidate.textContent || '').includes('BotFather');
    });
    if (!row) return null;
    row.scrollIntoView({ block: 'center' });
    const box = row.getBoundingClientRect();
    return { x: box.x + Math.min(160, box.width / 2), y: box.y + box.height / 2 };
  });

  assertSafe(rect, 'BotFather row was not found in Telegram chat list.');
  await page.mouse.click(rect.x, rect.y);
  await wait(2500);

  state = await activeChatState(page);
  assertSafe(state.ok && state.chatTextPrefix.includes('BotFather'), 'BotFather chat could not be focused.');
}

async function activeInputCenter(page) {
  const center = await page.evaluate(() => {
    const chat = document.querySelector('.chat.active') || document.querySelector('.chat');
    if (!chat) return null;
    const input = Array.from(chat.querySelectorAll('.input-message-input')).find((el) => {
      const box = el.getBoundingClientRect();
      const style = getComputedStyle(el);
      return box.width > 0 && box.height > 0 && style.display !== 'none' && style.visibility !== 'hidden' && Number(style.opacity) !== 0;
    });
    if (!input) return null;
    const box = input.getBoundingClientRect();
    return { x: box.x + box.width / 2, y: box.y + box.height / 2 };
  });
  assertSafe(center, 'BotFather message input is not visible.');
  return center;
}

async function sendCommand(page, command) {
  const center = await activeInputCenter(page);
  await page.mouse.click(center.x, center.y);
  await page.keyboard.type(command, { delay: 8 });
  await page.keyboard.press('Enter');
  await wait(4500);
}

async function clickLatestButton(page, label) {
  const rect = await page.evaluate((buttonLabel) => {
    const chat = document.querySelector('.chat.active') || document.querySelector('.chat');
    if (!chat) return null;
    const latestBubble = Array.from(chat.querySelectorAll('.bubble')).at(-1);
    if (!latestBubble) return null;
    const button = Array.from(latestBubble.querySelectorAll('.reply-markup-button')).find((el) => (el.textContent || '').trim() === buttonLabel);
    if (!button) return null;
    const box = button.getBoundingClientRect();
    return { x: box.x + box.width / 2, y: box.y + box.height / 2 };
  }, label);
  assertSafe(rect, `Button not found in latest BotFather reply: ${label}`);
  await page.mouse.click(rect.x, rect.y);
  await wait(4000);
}

async function scanBotList(page) {
  const seenPages = [];
  const aggregate = { targetCount: 0, activeCount: 0, pageCount: 0 };

  for (let pageIndex = 0; pageIndex < maxPages; pageIndex += 1) {
    const state = await activeChatState(page);
    assertSafe(state.ok, state.reason || 'BotFather state unavailable.');
    const buttons = state.latestButtons;
    aggregate.pageCount += 1;
    aggregate.targetCount += buttons.filter((text) => text === target).length;
    if (active) {
      aggregate.activeCount += buttons.filter((text) => text === active).length;
    }
    seenPages.push({
      page: pageIndex + 1,
      targetOnPage: buttons.includes(target),
      activeOnPage: active ? buttons.includes(active) : undefined,
      hasNext: buttons.includes('»'),
      buttonCount: buttons.length,
    });

    if (!buttons.includes('»')) {
      break;
    }
    await clickLatestButton(page, '»');
  }

  return { ...aggregate, seenPages };
}

async function clickTargetFromCurrentList(page) {
  for (let pageIndex = 0; pageIndex < maxPages; pageIndex += 1) {
    const state = await activeChatState(page);
    assertSafe(state.ok, state.reason || 'BotFather state unavailable.');
    const targetOnPage = state.latestButtons.filter((text) => text === target).length;
    if (targetOnPage === 1) {
      await clickLatestButton(page, target);
      return { page: pageIndex + 1 };
    }
    assertSafe(targetOnPage === 0, `Target appears more than once on page ${pageIndex + 1}.`);
    if (!state.latestButtons.includes('»')) {
      break;
    }
    await clickLatestButton(page, '»');
  }
  throw new Error('Target bot was not found in BotFather /mybots list.');
}

async function main() {
  assertSafe(target.startsWith('@'), 'Target username must start with @.');
  assertSafe(!active || active.startsWith('@'), 'Active username must start with @ when provided.');
  assertSafe(!active || target !== active, 'Refusing to delete because target equals active bot.');

  const browser = await chromium.connectOverCDP(cdpEndpoint);
  const context = browser.contexts()[0];
  assertSafe(context, 'No browser context found from CDP endpoint.');
  let page = context.pages().find((candidate) => candidate.url().includes('web.telegram.org/k'));
  assertSafe(page, 'No Telegram Web K page found. Open Telegram Web in the dedicated Windows Chrome profile first.');

  await focusBotFather(page);
  await sendCommand(page, '/mybots');
  const dryRunScan = await scanBotList(page);

  const dryRunReport = {
    mode: confirmDelete ? 'confirm-delete' : 'dry-run',
    target_count: dryRunScan.targetCount,
    active_count: active ? dryRunScan.activeCount : undefined,
    scanned_pages: dryRunScan.pageCount,
    pages: dryRunScan.seenPages,
  };

  if (!confirmDelete) {
    console.log(safeJson({ status: 'dry_run_complete', ...dryRunReport }));
    await browser.close();
    return;
  }

  assertSafe(dryRunScan.targetCount === 1, `Expected exactly one target in /mybots list, found ${dryRunScan.targetCount}.`);
  if (active) {
    assertSafe(dryRunScan.activeCount >= 1, 'Active bot was not found in /mybots list before deletion.');
  }

  await sendCommand(page, '/mybots');
  await clickTargetFromCurrentList(page);

  let state = await activeChatState(page);
  assertSafe(state.latestText.includes(target), 'Bot management menu does not name the target bot.');
  assertSafe(!active || !state.latestText.includes(active), 'Bot management menu unexpectedly names the active bot.');
  if (displayName) {
    assertSafe(state.latestText.includes(displayName), 'Bot management menu does not include the expected display name.');
  }

  await clickLatestButton(page, 'Delete Bot');
  state = await activeChatState(page);
  assertSafe(state.latestText.includes(target), 'First delete confirmation does not name the target bot.');
  assertSafe(!active || !state.latestText.includes(active), 'First delete confirmation unexpectedly names the active bot.');
  if (displayName) {
    assertSafe(state.latestText.includes(displayName), 'First delete confirmation does not include the expected display name.');
  }

  await clickLatestButton(page, 'Yes, delete the bot');
  state = await activeChatState(page);
  assertSafe(state.latestText.includes(target), 'Final delete confirmation does not name the target bot.');
  assertSafe(!active || !state.latestText.includes(active), 'Final delete confirmation unexpectedly names the active bot.');
  if (displayName) {
    assertSafe(state.latestText.includes(displayName), 'Final delete confirmation does not include the expected display name.');
  }

  await clickLatestButton(page, "Yes, I'm 100% sure!");
  state = await activeChatState(page);
  assertSafe(state.latestText.includes('deleted') && state.latestText.includes(target), 'BotFather did not confirm target deletion.');

  await sendCommand(page, '/mybots');
  const verifyScan = await scanBotList(page);
  assertSafe(verifyScan.targetCount === 0, `Target still appears in /mybots list after deletion: ${verifyScan.targetCount}.`);
  if (active) {
    assertSafe(verifyScan.activeCount >= 1, 'Active bot was not found in /mybots list after deletion.');
  }

  console.log(safeJson({
    status: 'deleted',
    target_count_after: verifyScan.targetCount,
    active_count_after: active ? verifyScan.activeCount : undefined,
    scanned_pages_after: verifyScan.pageCount,
    pages_after: verifyScan.seenPages,
  }));
  await browser.close();
}

main().catch((error) => {
  console.error(safeJson({ status: 'failed', error: error.message }));
  process.exit(1);
});
NODE
