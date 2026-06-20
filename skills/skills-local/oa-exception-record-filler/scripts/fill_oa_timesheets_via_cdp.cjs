#!/usr/bin/env node
'use strict';

const path = require('node:path');

const DEFAULT_CDP_ENDPOINT = process.env.OA_CDP_ENDPOINT || 'http://127.0.0.1:9222';
const OA_LIST_URL = 'http://oa.drlaser.com.cn:9000/spa/workflow/static/index.html#/main/workflow/listMine';
const POLICY_TIME_ZONE = 'Asia/Shanghai';
const WORKFLOW_TITLE = '技术服务部-工时分配单';
const OVERTIME_WORKFLOW_TITLE = '加班单（客服）';
const CUSTOMER_ID = '823';
const CUSTOMER_NAME = '扬州晶澳';
const PAID_TRANSFORM_NO_VALUE = '1';
const PAID_TRANSFORM_NO_NAME = '否';
const MODULE_ID = '2';
const MODULE_NAME = '运维模块';

const FIELD_IDS = {
  assignedDate: 'field10961',
  customer: 'field10966',
  paidTransform: 'field10972',
  overtime: 'field10963',
  attendance: 'field10964',
  total: 'field10965',
  detailTotal: 'field10973',
  module: 'field10968_0',
  serial: 'field10974_0',
  duration: 'field10971_0',
  remark: 'field11039_0',
};

const OVERTIME_FIELD_IDS = {
  startDate: 'field7205',
  endDate: 'field7206',
  duration: 'field7212',
};

const MAY_2026_REST_DAYS = new Set([
  '2026-05-01',
  '2026-05-02',
  '2026-05-03',
  '2026-05-04',
  '2026-05-05',
  '2026-05-10',
  '2026-05-16',
  '2026-05-17',
  '2026-05-24',
  '2026-05-30',
  '2026-05-31',
]);

const MAY_2026_WORK_DAYS = new Set([
  '2026-05-06',
  '2026-05-07',
  '2026-05-08',
  '2026-05-09',
  '2026-05-11',
  '2026-05-12',
  '2026-05-13',
  '2026-05-14',
  '2026-05-15',
  '2026-05-18',
  '2026-05-19',
  '2026-05-20',
  '2026-05-21',
  '2026-05-22',
  '2026-05-23',
  '2026-05-25',
  '2026-05-26',
  '2026-05-27',
  '2026-05-28',
  '2026-05-29',
]);

const JUN_2026_REST_DAYS = new Set([
  '2026-06-07',
  '2026-06-08',
  '2026-06-14',
  '2026-06-15',
  '2026-06-21',
  '2026-06-22',
  '2026-06-28',
  '2026-06-29',
]);

const JUN_2026_WORK_DAYS = new Set([
  '2026-06-01',
  '2026-06-02',
  '2026-06-03',
  '2026-06-04',
  '2026-06-05',
  '2026-06-06',
  '2026-06-09',
  '2026-06-10',
  '2026-06-11',
  '2026-06-12',
  '2026-06-13',
  '2026-06-16',
  '2026-06-17',
  '2026-06-18',
  '2026-06-19',
  '2026-06-20',
  '2026-06-23',
  '2026-06-24',
  '2026-06-25',
  '2026-06-26',
  '2026-06-27',
  '2026-06-30',
]);

function printUsage() {
  console.log(`Usage:
  fill_oa_timesheets_via_cdp.cjs --overtime-entry YYYY-MM-DD:OVERTIME_HOURS [--overtime-entry YYYY-MM-DD:OVERTIME_HOURS] [options]
  fill_oa_timesheets_via_cdp.cjs --auto-from-list [--since YYYY-MM-DD] [--until YYYY-MM-DD] [options]

Options:
  --overtime-entry DATE:OVERTIME[:ATTENDANCE]
                                  Fill one assigned date from overtime hours. Total is ATTENDANCE + OVERTIME.
  --entry DATE:TOTAL[:ATTENDANCE]  Fill one assigned date from total hours. Overtime is TOTAL - ATTENDANCE.
  --auto-from-list                 Discover recent timesheets and matching overtime forms from the OA list.
  --list-url URL                   OA list URL to open when no list page is already active. Default: sanitized listMine URL.
  --scan-pages N                   Number of OA list pages to scan for timesheets/overtime forms. Default: 3.
  --since YYYY-MM-DD               Auto mode lower bound for assigned dates.
  --until YYYY-MM-DD               Auto mode upper bound for assigned dates.
  --today YYYY-MM-DD               Business date for the overtime 24h window. Default: Asia/Shanghai today.
  --cdp-endpoint URL               Chrome DevTools endpoint. Default: ${DEFAULT_CDP_ENDPOINT}
  --dry-run                        Open and verify matching forms without saving.
  --verify-only                    Verify current forms against planned values without saving.
  --fill-missing                   Save only forms whose current values do not match planned values.
  --help                           Show this help.

Examples:
  fill_oa_timesheets_via_cdp.cjs --auto-from-list --since 2026-05-16 --until 2026-05-24
  fill_oa_timesheets_via_cdp.cjs --overtime-entry 2026-05-16:12 --overtime-entry 2026-05-17:11.5
  fill_oa_timesheets_via_cdp.cjs --overtime-entry 2026-05-20:0
  fill_oa_timesheets_via_cdp.cjs --entry 2026-05-18:8:8 --dry-run
  fill_oa_timesheets_via_cdp.cjs --auto-from-list --since 2026-06-01 --until 2026-06-16 --verify-only
  fill_oa_timesheets_via_cdp.cjs --auto-from-list --since 2026-06-01 --until 2026-06-16 --fill-missing
`);
}

function parseArgs(argv) {
  const options = {
    cdpEndpoint: DEFAULT_CDP_ENDPOINT,
    dryRun: false,
    verifyOnly: false,
    fillMissing: false,
    entries: [],
    autoFromList: false,
    listUrl: OA_LIST_URL,
    scanPages: 3,
    since: undefined,
    until: undefined,
    today: localDateInPolicyTimezone(),
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--help' || arg === '-h') {
      printUsage();
      process.exit(0);
    }
    if (arg === '--dry-run') {
      options.dryRun = true;
      continue;
    }
    if (arg === '--verify-only') {
      options.verifyOnly = true;
      continue;
    }
    if (arg === '--fill-missing') {
      options.fillMissing = true;
      continue;
    }
    if (arg === '--cdp-endpoint') {
      index += 1;
      options.cdpEndpoint = requireValue(argv[index], arg);
      continue;
    }
    if (arg === '--list-url') {
      index += 1;
      options.listUrl = stripSensitiveListUrl(requireValue(argv[index], arg));
      continue;
    }
    if (arg === '--scan-pages') {
      index += 1;
      options.scanPages = parsePositiveInteger(requireValue(argv[index], arg), arg);
      continue;
    }
    if (arg === '--since') {
      index += 1;
      options.since = parseDateArg(requireValue(argv[index], arg), arg);
      continue;
    }
    if (arg === '--until') {
      index += 1;
      options.until = parseDateArg(requireValue(argv[index], arg), arg);
      continue;
    }
    if (arg === '--today') {
      index += 1;
      options.today = parseDateArg(requireValue(argv[index], arg), arg);
      continue;
    }
    if (arg === '--auto-from-list') {
      options.autoFromList = true;
      continue;
    }
    if (arg === '--entry') {
      index += 1;
      options.entries.push(parseEntry(requireValue(argv[index], arg)));
      continue;
    }
    if (arg === '--overtime-entry') {
      index += 1;
      options.entries.push(parseOvertimeEntry(requireValue(argv[index], arg)));
      continue;
    }
    throw new Error(`Unknown argument: ${arg}`);
  }

  if (options.entries.length === 0 && !options.autoFromList) {
    throw new Error('At least one --overtime-entry/--entry or --auto-from-list is required.');
  }
  if (options.since && options.until && options.since > options.until) {
    throw new Error(`Invalid date range: --since ${options.since} is after --until ${options.until}.`);
  }
  if (options.verifyOnly && options.fillMissing) {
    throw new Error('--verify-only and --fill-missing cannot be used together.');
  }

  return options;
}

function requireValue(value, flag) {
  if (!value || value.startsWith('--')) {
    throw new Error(`Missing value for ${flag}`);
  }
  return value;
}

function parsePositiveInteger(raw, label) {
  const value = Number(raw);
  if (!Number.isInteger(value) || value <= 0) {
    throw new Error(`Invalid ${label}: ${raw}`);
  }
  return value;
}

function parseDateArg(raw, label) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(raw)) {
    throw new Error(`Invalid ${label}: ${raw}`);
  }
  return raw;
}

function stripSensitiveListUrl(rawUrl) {
  const url = new URL(rawUrl);
  if (!url.href.includes('oa.drlaser.com.cn')) {
    throw new Error(`Refusing non-OA list URL: ${url.origin}`);
  }
  url.search = '';
  if (url.hash.includes('?')) {
    url.hash = url.hash.slice(0, url.hash.indexOf('?'));
  }
  return url.toString();
}

function parseEntry(raw) {
  const parts = raw.split(':');
  if (parts.length < 2 || parts.length > 3) {
    throw new Error(`Invalid --entry "${raw}". Expected DATE:TOTAL[:ATTENDANCE].`);
  }

  const [date, totalRaw, attendanceRaw] = parts;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    throw new Error(`Invalid date in --entry "${raw}".`);
  }

  const total = parseFiniteNumber(totalRaw, `total hours for ${date}`);
  const attendance = attendanceRaw === undefined
    ? attendanceForDate(date)
    : parseFiniteNumber(attendanceRaw, `attendance hours for ${date}`);
  const overtime = total - attendance;
  if (overtime < 0) {
    throw new Error(`Computed overtime is negative for ${date}. total=${total}, attendance=${attendance}`);
  }

  return {
    date,
    titleDateCandidates: unique([addDays(date, 1), date]),
    attendance: formatHours(attendance),
    overtime: formatHours(overtime),
    total: formatHours(total),
  };
}

function parseOvertimeEntry(raw) {
  const parts = raw.split(':');
  if (parts.length < 2 || parts.length > 3) {
    throw new Error(`Invalid --overtime-entry "${raw}". Expected DATE:OVERTIME[:ATTENDANCE].`);
  }

  const [date, overtimeRaw, attendanceRaw] = parts;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    throw new Error(`Invalid date in --overtime-entry "${raw}".`);
  }

  const overtime = parseFiniteNumber(overtimeRaw, `overtime hours for ${date}`);
  if (overtime < 0) {
    throw new Error(`Invalid overtime hours for ${date}: ${overtimeRaw}`);
  }
  const attendance = attendanceRaw === undefined
    ? attendanceForDate(date)
    : parseFiniteNumber(attendanceRaw, `attendance hours for ${date}`);
  const total = attendance + overtime;

  return {
    date,
    titleDateCandidates: unique([addDays(date, 1), date]),
    attendance: formatHours(attendance),
    overtime: formatHours(overtime),
    total: formatHours(total),
  };
}

function parseFiniteNumber(raw, label) {
  const value = Number(raw);
  if (!Number.isFinite(value)) {
    throw new Error(`Invalid ${label}: ${raw}`);
  }
  return value;
}

function attendanceForDate(date) {
  if (MAY_2026_REST_DAYS.has(date) || JUN_2026_REST_DAYS.has(date)) {
    return 0;
  }
  if (MAY_2026_WORK_DAYS.has(date) || JUN_2026_WORK_DAYS.has(date)) {
    return 8;
  }
  throw new Error(`No attendance rule for ${date}. Use --entry DATE:TOTAL:ATTENDANCE.`);
}

function formatHours(value) {
  return Number(value).toFixed(2);
}

function addDays(date, days) {
  const parsed = new Date(`${date}T00:00:00Z`);
  if (Number.isNaN(parsed.getTime())) {
    throw new Error(`Invalid date: ${date}`);
  }
  parsed.setUTCDate(parsed.getUTCDate() + days);
  return parsed.toISOString().slice(0, 10);
}

function localDateInPolicyTimezone() {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: POLICY_TIME_ZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date());
}

function unique(values) {
  return [...new Set(values)];
}

function normalizeText(text) {
  return String(text || '').replace(/\s+/g, ' ').trim();
}

function debugLog(message, details = undefined) {
  if (!process.env.OA_DEBUG) {
    return;
  }
  if (details === undefined) {
    console.error(`[oa-debug] ${message}`);
    return;
  }
  console.error(`[oa-debug] ${message} ${JSON.stringify(details)}`);
}

function dateInRange(date, options) {
  return (!options.since || date >= options.since) && (!options.until || date <= options.until);
}

function isInOpenOvertimeWindow(date, today) {
  return date === today || date === addDays(today, -1);
}

function parseTimesheetTitleDate(text) {
  const matches = normalizeText(text).match(/\d{4}-\d{2}-\d{2}/g);
  return matches ? matches[matches.length - 1] : undefined;
}

function parseOvertimeStartDateFromText(text) {
  const match = normalizeText(text).match(/开始：\s*(\d{4}-\d{2}-\d{2})/);
  return match ? match[1] : undefined;
}

function makeAutoEntry(date, overtime, sourceItem, overtimeSource) {
  const attendance = attendanceForDate(date);
  const total = attendance + overtime;
  return {
    date,
    titleDateCandidates: unique([addDays(date, 1), date]),
    attendance: formatHours(attendance),
    overtime: formatHours(overtime),
    total: formatHours(total),
    sourceItem,
    overtimeSource,
  };
}

function loadPlaywright() {
  try {
    return require('playwright');
  } catch {
    const candidates = [
      process.env.PLAYWRIGHT_NODE_PATH,
      path.join(process.env.HOME || '', '.nvm/versions/node/v20.20.2/lib/node_modules/@playwright/cli/node_modules'),
    ].filter(Boolean);

    for (const candidate of candidates) {
      try {
        return require(path.join(candidate, 'playwright'));
      } catch {
        // Keep trying fallback paths.
      }
    }
  }

  throw new Error('Cannot load playwright. Set PLAYWRIGHT_NODE_PATH to the @playwright/cli node_modules path.');
}

function sanitizePage(page) {
  return {
    title: page.title,
    assignedDate: page.assignedDate,
    customer: page.customer,
    paidTransform: page.paidTransform,
    attendance: page.attendance,
    overtime: page.overtime,
    total: page.total,
    detailTotal: page.detailTotal,
    module: page.module,
    duration: page.duration,
    serial: page.serial,
    remark: page.remark,
  };
}

async function waitForWfForm(page) {
  await page.waitForLoadState('domcontentloaded', { timeout: 15000 }).catch(() => undefined);
  await page.waitForFunction(() => Boolean(window.WfForm), undefined, { timeout: 30000 });
  await page.waitForFunction(
    (id) => {
      try { return (window.WfForm.getFieldValue(id) || '') !== ''; } catch { return false; }
    },
    FIELD_IDS.assignedDate,
    { timeout: 15000 },
  ).catch(() => undefined);
}

async function readForm(page) {
  await waitForWfForm(page);
  return page.evaluate((fieldIds) => {
    const form = window.WfForm;
    const read = (reader) => {
      try {
        return reader() || '';
      } catch {
        return '';
      }
    };

    return {
      title: document.title,
      assignedDate: read(() => form.getFieldValue(fieldIds.assignedDate)),
      customer: read(() => form.getBrowserShowName(fieldIds.customer)),
      paidTransform: read(() => form.getSelectShowName(fieldIds.paidTransform)),
      attendance: read(() => form.getFieldValue(fieldIds.attendance)),
      overtime: read(() => form.getFieldValue(fieldIds.overtime)),
      total: read(() => form.getFieldValue(fieldIds.total)),
      detailTotal: read(() => form.getFieldValue(fieldIds.detailTotal)),
      module: read(() => form.getSelectShowName(fieldIds.module)),
      duration: read(() => form.getFieldValue(fieldIds.duration)),
      serial: read(() => form.getBrowserShowName(fieldIds.serial)),
      remark: read(() => form.getFieldValue(fieldIds.remark)),
    };
  }, FIELD_IDS);
}

async function waitForTimesheetForm(page, expectedAssignedDate, titleDate, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  let lastForm;

  while (Date.now() <= deadline) {
    const form = await readForm(page);
    lastForm = form;
    const titleMatches = !titleDate || form.title.includes(titleDate);
    const dateMatches = !expectedAssignedDate || form.assignedDate === expectedAssignedDate;
    if (titleMatches && dateMatches) {
      return form;
    }
    await page.waitForTimeout(500);
  }

  throw new Error(`Timesheet form did not stabilize. expectedTitleDate=${titleDate || ''} expectedAssignedDate=${expectedAssignedDate || ''} actualTitle=${lastForm ? lastForm.title : ''} actualAssignedDate=${lastForm ? lastForm.assignedDate : ''}`);
}

async function findExistingFormPage(context, assignedDate) {
  for (const page of context.pages()) {
    if (!isOaWorkflowFormPage(page)) {
      continue;
    }
    try {
      await page.bringToFront();
      const form = await readForm(page);
      if (form.assignedDate === assignedDate) {
        return page;
      }
    } catch {
      // Ignore non-form or still-loading pages.
    }
  }
  return undefined;
}

function isOaWorkflowFormPage(page) {
  const url = page.url();
  return url.includes('oa.drlaser.com.cn') &&
    (url.includes('/main/workflow/req') || url.includes('static4form'));
}

async function findExistingTimesheetPageByTitleDate(context, titleDate, expectedAssignedDate) {
  for (const page of context.pages()) {
    if (!isOaWorkflowFormPage(page)) {
      continue;
    }
    try {
      const title = await page.title();
      if (!title.includes(WORKFLOW_TITLE) || !title.includes(titleDate)) {
        continue;
      }
      await page.bringToFront();
      return { page, form: await waitForTimesheetForm(page, expectedAssignedDate, titleDate, 12000) };
    } catch {
      // Keep scanning candidate tabs.
    }
  }
  return undefined;
}

async function findExistingOvertimePage(context, assignedDate) {
  for (const page of context.pages()) {
    if (!isOaWorkflowFormPage(page)) {
      continue;
    }
    try {
      const title = await page.title();
      if (!title.includes(OVERTIME_WORKFLOW_TITLE)) {
        continue;
      }
      const form = await readOvertimeForm(page);
      if (form.startDate === assignedDate) {
        await page.bringToFront();
        return { page, form };
      }
    } catch {
      // Keep scanning candidate tabs.
    }
  }
  return undefined;
}

async function getListPage(context, listUrl = OA_LIST_URL) {
  const pages = [...context.pages()].reverse();
  const listPage = pages.find(page => {
    const url = page.url();
    return url.includes('oa.drlaser.com.cn') &&
      url.includes('/spa/workflow/static/index.html') &&
      (url.includes('listMine') || url.includes('queryFlow'));
  });

  if (listPage) {
    return listPage;
  }

  const page = await context.newPage();
  await page.goto(listUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
  return page;
}

function escapeRegExp(text) {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

async function waitForListReady(page) {
  await page.waitForLoadState('domcontentloaded', { timeout: 15000 }).catch(() => undefined);
  await page.waitForFunction(
    () => document.body && /我的请求|流程标题|技术服务部-工时分配单|加班单/.test(document.body.innerText || ''),
    undefined,
    { timeout: 20000 },
  ).catch(() => undefined);
  await page.waitForTimeout(800);
}

async function resetListFilters(listPage) {
  const allType = listPage.getByText('全部类型', { exact: true }).first();
  if (await allType.count() > 0) {
    await allType.click().catch(() => undefined);
    await listPage.waitForTimeout(1500);
  }

  const allTab = listPage.getByText('全部', { exact: true }).first();
  if (await allTab.count() > 0) {
    await allTab.click().catch(() => undefined);
    await listPage.waitForTimeout(1500);
  }

  await waitForListReady(listPage);
}

async function navigateListPage(listPage, pageNumber) {
  await listPage.bringToFront();
  await waitForListReady(listPage);
  const activeText = await listPage.locator('li.ant-pagination-item-active').first().innerText().catch(() => '');
  if (normalizeText(activeText) === String(pageNumber)) {
    return;
  }

  const pageLink = listPage.locator(`li.ant-pagination-item-${pageNumber} a`).first();
  if (await pageLink.count() === 0) {
    const isFirstPage =
      pageNumber === 1 &&
      await listPage.locator('li.ant-pagination-first.ant-pagination-disabled').first().count() > 0;
    if (isFirstPage) {
      return;
    }

    if (pageNumber === 1) {
      const firstPageButton = listPage.locator('li.ant-pagination-first:not(.ant-pagination-disabled)').first();
      if (await firstPageButton.count() > 0) {
        await firstPageButton.click();
        await listPage.waitForFunction(
          () => {
            const active = document.querySelector('li.ant-pagination-item-active');
            const first = document.querySelector('li.ant-pagination-first');
            return (active && (active.textContent || '').trim() === '1') ||
              (first && first.className.includes('ant-pagination-disabled'));
          },
          undefined,
          { timeout: 10000 },
        ).catch(() => undefined);
        await waitForListReady(listPage);
        await listPage.waitForTimeout(1200);
        return;
      }
    }

    const quickJumper = listPage.locator('.ant-pagination-options-quick-jumper input').first();
    if (await quickJumper.count() > 0) {
      await quickJumper.fill(String(pageNumber));
      await quickJumper.press('Enter');
      await listPage.waitForFunction(
        (expectedPageNumber) => {
          const active = document.querySelector('li.ant-pagination-item-active');
          return active && (active.textContent || '').trim() === String(expectedPageNumber);
        },
        pageNumber,
        { timeout: 10000 },
      ).catch(() => undefined);
      await waitForListReady(listPage);
      await listPage.waitForTimeout(1200);
      return;
    }
    throw new Error(`OA list page ${pageNumber} is not available in the pagination controls.`);
  }
  await pageLink.click();
  await listPage.waitForFunction(
    (expectedPageNumber) => {
      const active = document.querySelector('li.ant-pagination-item-active');
      return active && (active.textContent || '').trim() === String(expectedPageNumber);
    },
    pageNumber,
    { timeout: 10000 },
  ).catch(() => undefined);
  await waitForListReady(listPage);
  await listPage.waitForTimeout(1200);
}

async function collectListItems(listPage, pageNumber) {
  await waitForListReady(listPage);
  return listPage.evaluate((payload) => {
    const normalize = (text) => String(text || '').replace(/\s+/g, ' ').trim();
    const rowSelectors = ['tr', '.ant-table-row'];
    const rowElements = Array.from(document.querySelectorAll(rowSelectors.join(',')));
    const seen = new Set();
    const items = [];

    for (const row of rowElements) {
      const rowText = normalize(row.innerText || row.textContent || '');
      if (!rowText || seen.has(rowText)) {
        continue;
      }
      seen.add(rowText);

      const anchors = Array.from(row.querySelectorAll('a'))
        .map(anchor => normalize(anchor.innerText || anchor.textContent || ''))
        .filter(Boolean);
      const anchorText = anchors.find(text => text.includes(payload.timesheetTitle) || text.includes(payload.overtimeTitle));
      if (!anchorText) {
        continue;
      }

      let type = '';
      if (anchorText.includes(payload.timesheetTitle)) {
        type = 'timesheet';
      } else if (anchorText.includes(payload.overtimeTitle)) {
        type = 'overtime';
      }
      if (!type) {
        continue;
      }

      items.push({
        type,
        pageNumber: payload.pageNumber,
        anchorText,
        rowText,
      });
    }

    return items;
  }, {
    pageNumber,
    timesheetTitle: WORKFLOW_TITLE,
    overtimeTitle: OVERTIME_WORKFLOW_TITLE,
  });
}

async function scanListItems(context, options) {
  const listPage = await getListPage(context, options.listUrl);
  await listPage.bringToFront();
  await listPage.goto(options.listUrl, { waitUntil: 'domcontentloaded', timeout: 30000 }).catch(() => undefined);
  await waitForListReady(listPage);
  await resetListFilters(listPage);

  const items = [];
  for (let pageNumber = 1; pageNumber <= options.scanPages; pageNumber += 1) {
    await navigateListPage(listPage, pageNumber);
    const pageItems = await collectListItems(listPage, pageNumber);
    debugLog('list-page-items', { pageNumber, count: pageItems.length });
    items.push(...pageItems);
  }
  return { listPage, items };
}

function getFilteredTimesheetItems(items, options) {
  for (const item of items.filter(candidate => candidate.type === 'timesheet')) {
    const titleDate = parseTimesheetTitleDate(item.anchorText);
    if (!titleDate) {
      continue;
    }
    item.titleDate = titleDate;
    item.expectedAssignedDate = addDays(titleDate, -1);
  }
  return items
    .filter(candidate => candidate.type === 'timesheet' &&
      candidate.titleDate &&
      dateInRange(candidate.expectedAssignedDate, options))
    .sort((a, b) => a.titleDate.localeCompare(b.titleDate));
}

function getOvertimeItemsByDate(items) {
  const byDate = new Map();
  for (const item of items.filter(candidate => candidate.type === 'overtime')) {
    const startDate = parseOvertimeStartDateFromText(item.anchorText);
    if (!startDate) {
      continue;
    }
    const existing = byDate.get(startDate) || [];
    existing.push({
      ...item,
      startDate,
    });
    byDate.set(startDate, existing);
  }
  return byDate;
}

async function openListItem(context, listPage, item) {
  await navigateListPage(listPage, item.pageNumber);
  await listPage.waitForFunction(
    (expectedText) => (document.body && (document.body.innerText || '').includes(expectedText)),
    item.anchorText,
    { timeout: 10000 },
  ).catch(() => undefined);
  const pattern = new RegExp(`^${escapeRegExp(item.anchorText)}$`);
  let link = listPage.getByRole('link', { name: pattern }).first();
  if (await link.count() === 0) {
    link = listPage.locator('a').filter({ hasText: item.anchorText }).first();
  }
  if (await link.count() === 0) {
    throw new Error(`Could not find OA list link "${item.anchorText}" on page ${item.pageNumber}.`);
  }

  const before = new Set(context.pages());
  const pagePromise = context.waitForEvent('page', { timeout: 8000 }).catch(() => undefined);
  await link.click();
  const newPage = await pagePromise;
  const page = newPage || context.pages().find(candidate => !before.has(candidate)) || listPage;
  await page.bringToFront();
  return { page, openedNewPage: Boolean(newPage || context.pages().find(candidate => !before.has(candidate))) };
}

async function readOvertimeForm(page) {
  await page.waitForLoadState('domcontentloaded', { timeout: 15000 }).catch(() => undefined);
  await page.waitForFunction(
    (workflowTitle) => Boolean(window.WfForm) &&
      ((document.title || '').includes(workflowTitle) || (document.body && (document.body.innerText || '').includes(workflowTitle))),
    OVERTIME_WORKFLOW_TITLE,
    { timeout: 30000 },
  );
  await page.waitForTimeout(1200);
  return page.evaluate((fieldIds) => {
    const form = window.WfForm;
    const read = (fieldId) => {
      try {
        return form.getFieldValue(fieldId) || '';
      } catch {
        return '';
      }
    };
    return {
      title: document.title,
      startDate: read(fieldIds.startDate),
      endDate: read(fieldIds.endDate),
      duration: read(fieldIds.duration),
    };
  }, OVERTIME_FIELD_IDS);
}

async function resolveOvertimeHours(context, listPage, timesheetItems, overtimeItemsByDate, options) {
  const hoursByDate = new Map();
  const sourceByDate = new Map();
  const skipped = [];

  for (const timesheetItem of timesheetItems) {
    const overtimeItems = overtimeItemsByDate.get(timesheetItem.assignedDate) || [];
    if (overtimeItems.length === 0) {
      if (isInOpenOvertimeWindow(timesheetItem.assignedDate, options.today)) {
        skipped.push({
          date: timesheetItem.assignedDate,
          reason: 'within 24h overtime filing window and no matching submitted overtime form was found',
          titleDate: timesheetItem.titleDate,
        });
        sourceByDate.set(timesheetItem.assignedDate, {
          skipped: true,
          reason: 'within 24h overtime filing window and no matching submitted overtime form was found',
        });
        continue;
      }
      hoursByDate.set(timesheetItem.assignedDate, 0);
      sourceByDate.set(timesheetItem.assignedDate, {
        found: false,
        reason: 'no matching overtime form in scanned list pages',
      });
      continue;
    }
    if (overtimeItems.length > 1) {
      throw new Error(`Found multiple filled overtime forms for ${timesheetItem.assignedDate}; refusing to guess.`);
    }

    const overtimeItem = overtimeItems[0];
    const existing = await findExistingOvertimePage(context, timesheetItem.assignedDate);
    let page = existing ? existing.page : undefined;
    let form = existing ? existing.form : undefined;
    let openedNewPage = false;
    if (!page || !form) {
      const opened = await openListItem(context, listPage, overtimeItem);
      page = opened.page;
      openedNewPage = opened.openedNewPage;
      try {
        form = await readOvertimeForm(page);
      } catch (error) {
        const focusedExisting = await findExistingOvertimePage(context, timesheetItem.assignedDate);
        if (!focusedExisting) {
          throw error;
        }
        page = focusedExisting.page;
        form = focusedExisting.form;
        openedNewPage = false;
      }
      if (form.startDate !== timesheetItem.assignedDate) {
        const focusedExisting = await findExistingOvertimePage(context, timesheetItem.assignedDate);
        if (focusedExisting) {
          page = focusedExisting.page;
          form = focusedExisting.form;
          openedNewPage = false;
        }
      }
    }

    const rawDuration = normalizeText(form.duration);
    if (!rawDuration && isInOpenOvertimeWindow(timesheetItem.assignedDate, options.today)) {
      skipped.push({
        date: timesheetItem.assignedDate,
        reason: 'within 24h overtime filing window and matching overtime form has blank duration',
        titleDate: timesheetItem.titleDate,
        overtimeStartDate: form.startDate,
        overtimeEndDate: form.endDate,
      });
      sourceByDate.set(timesheetItem.assignedDate, {
        skipped: true,
        reason: 'within 24h overtime filing window and matching overtime form has blank duration',
      });
      if (openedNewPage && page) {
        await page.close().catch(() => undefined);
      }
      continue;
    }

    const overtimeHours = rawDuration ? parseFiniteNumber(rawDuration, `overtime duration for ${timesheetItem.assignedDate}`) : 0;
    if (form.startDate && form.startDate !== timesheetItem.assignedDate) {
      throw new Error(`Overtime form date mismatch. expected=${timesheetItem.assignedDate} actual=${form.startDate}`);
    }
    if (openedNewPage && page) {
      await page.close().catch(() => undefined);
    }

    hoursByDate.set(timesheetItem.assignedDate, overtimeHours);
    sourceByDate.set(timesheetItem.assignedDate, {
      found: true,
      title: form.title,
      startDate: form.startDate,
      endDate: form.endDate,
      duration: formatHours(overtimeHours),
    });
  }

  return { hoursByDate, sourceByDate, skipped };
}

async function resolveTimesheetAssignedDates(context, listPage, timesheetItems, options) {
  const byAssignedDate = new Map();

  for (const item of timesheetItems) {
    const existing = await findExistingTimesheetPageByTitleDate(context, item.titleDate, item.expectedAssignedDate);
    let page = existing ? existing.page : undefined;
    let form = existing ? existing.form : undefined;
    let openedNewPage = false;
    if (!page || !form) {
      const opened = await openListItem(context, listPage, item);
      page = opened.page;
      openedNewPage = opened.openedNewPage;
      try {
        form = await waitForTimesheetForm(page, item.expectedAssignedDate, item.titleDate, 15000);
      } catch (error) {
        const focusedExisting = await findExistingTimesheetPageByTitleDate(context, item.titleDate, item.expectedAssignedDate);
        if (!focusedExisting) {
          throw error;
        }
        page = focusedExisting.page;
        form = focusedExisting.form;
        openedNewPage = false;
      }
      if (!form.title.includes(item.titleDate) || form.assignedDate !== item.expectedAssignedDate) {
        const focusedExisting = await findExistingTimesheetPageByTitleDate(context, item.titleDate, item.expectedAssignedDate);
        if (focusedExisting) {
          page = focusedExisting.page;
          form = focusedExisting.form;
          openedNewPage = false;
        }
      }
    }
    if (openedNewPage && page) {
      await page.close().catch(() => undefined);
    }
    if (!form.assignedDate) {
      throw new Error(`Could not read assigned date from timesheet "${item.anchorText}".`);
    }
    debugLog('timesheet-date', {
      titleDate: item.titleDate,
      expectedAssignedDate: item.expectedAssignedDate,
      assignedDate: form.assignedDate,
      title: form.title,
    });
    if (!dateInRange(form.assignedDate, options)) {
      continue;
    }
    if (!byAssignedDate.has(form.assignedDate)) {
      byAssignedDate.set(form.assignedDate, {
        ...item,
        assignedDate: form.assignedDate,
      });
    }
  }

  return [...byAssignedDate.values()].sort((a, b) => a.assignedDate.localeCompare(b.assignedDate));
}

async function buildAutoEntriesFromList(context, options) {
  const { listPage, items } = await scanListItems(context, options);
  const timesheetCandidates = getFilteredTimesheetItems(items, options);
  const timesheetItems = await resolveTimesheetAssignedDates(context, listPage, timesheetCandidates, options);
  if (timesheetItems.length === 0) {
    throw new Error('No matching timesheet rows were found in the scanned OA list pages.');
  }

  const overtimeItemsByDate = getOvertimeItemsByDate(items);
  const { hoursByDate, sourceByDate, skipped } = await resolveOvertimeHours(context, listPage, timesheetItems, overtimeItemsByDate, options);

  const entries = timesheetItems
    .filter(item => {
      const source = sourceByDate.get(item.assignedDate);
      return !source || !source.skipped;
    })
    .map((item) => {
      const overtime = hoursByDate.get(item.assignedDate) || 0;
      return makeAutoEntry(item.assignedDate, overtime, item, sourceByDate.get(item.assignedDate));
    });

  return { entries, skipped };
}

async function openFormFromList(context, entry) {
  const listPage = await getListPage(context);
  await listPage.bringToFront();
  await listPage.waitForLoadState('domcontentloaded', { timeout: 15000 }).catch(() => undefined);

  if (entry.sourceItem) {
    const { page } = await openListItem(context, listPage, entry.sourceItem);
    const form = await waitForTimesheetForm(page, entry.date, entry.sourceItem.titleDate, 15000);
    if (form.assignedDate === entry.date) {
      return page;
    }
    throw new Error(`Opened wrong timesheet from list. expected=${entry.date} actual=${form.assignedDate}`);
  }

  for (const titleDate of entry.titleDateCandidates) {
    const linkPattern = new RegExp(`${escapeRegExp(WORKFLOW_TITLE)}.*${escapeRegExp(titleDate)}`);
    const links = listPage.getByRole('link', { name: linkPattern });
    if (await links.count() === 0) {
      continue;
    }

    const before = new Set(context.pages());
    const pagePromise = context.waitForEvent('page', { timeout: 6000 }).catch(() => undefined);
    await links.first().click();
    const newPage = await pagePromise;
    const page = newPage || context.pages().find(candidate => !before.has(candidate)) || listPage;
    await page.bringToFront();
    const form = await readForm(page);
    if (form.assignedDate === entry.date) {
      return page;
    }
  }

  throw new Error(`Could not open a form whose ${FIELD_IDS.assignedDate} is ${entry.date}.`);
}

async function resolveFormPage(context, entry) {
  if (entry.sourceItem) {
    const existing = await findExistingTimesheetPageByTitleDate(context, entry.sourceItem.titleDate, entry.date);
    if (existing) {
      return existing.page;
    }
    return openFormFromList(context, entry);
  }

  const existing = await findExistingFormPage(context, entry.date);
  if (existing) {
    return existing;
  }
  return openFormFromList(context, entry);
}

async function fillForm(page, entry) {
  await waitForWfForm(page);
  return page.evaluate((payload) => {
    const form = window.WfForm;
    const assignedDate = form.getFieldValue(payload.fieldIds.assignedDate);
    if (assignedDate !== payload.entry.date) {
      throw new Error(`Refusing to fill wrong assigned date. expected=${payload.entry.date} actual=${assignedDate}`);
    }

    form.changeFieldValue(payload.fieldIds.customer, {
      value: payload.customer.id,
      specialobj: [{ id: payload.customer.id, name: payload.customer.name }],
    });
    form.changeFieldValue(payload.fieldIds.paidTransform, { value: payload.paidTransform.value });
    form.changeFieldValue(payload.fieldIds.attendance, { value: payload.entry.attendance });
    form.changeFieldValue(payload.fieldIds.overtime, { value: payload.entry.overtime });
    form.changeFieldValue(payload.fieldIds.module, { value: payload.module.value });
    form.changeFieldValue(payload.fieldIds.duration, { value: payload.entry.total });

    return {
      assignedDate: form.getFieldValue(payload.fieldIds.assignedDate),
      customer: form.getBrowserShowName(payload.fieldIds.customer),
      paidTransform: form.getSelectShowName(payload.fieldIds.paidTransform),
      attendance: form.getFieldValue(payload.fieldIds.attendance),
      overtime: form.getFieldValue(payload.fieldIds.overtime),
      total: form.getFieldValue(payload.fieldIds.total),
      detailTotal: form.getFieldValue(payload.fieldIds.detailTotal),
      module: form.getSelectShowName(payload.fieldIds.module),
      duration: form.getFieldValue(payload.fieldIds.duration),
      serial: form.getBrowserShowName(payload.fieldIds.serial),
      remark: form.getFieldValue(payload.fieldIds.remark),
    };
  }, {
    entry,
    fieldIds: FIELD_IDS,
    customer: { id: CUSTOMER_ID, name: CUSTOMER_NAME },
    paidTransform: { value: PAID_TRANSFORM_NO_VALUE, name: PAID_TRANSFORM_NO_NAME },
    module: { value: MODULE_ID, name: MODULE_NAME },
  });
}

async function hasSaveButton(page) {
  // Check for save button using multiple strategies
  const saveButtonByRole = page.getByRole('button', { name: /保\s*存/ }).first();
  if (await saveButtonByRole.count() > 0) {
    return true;
  }
  // Also try checking the page content directly
  const hasSave = await page.evaluate(() => {
    // Look for any button-like element with "保存" text
    const buttons = Array.from(document.querySelectorAll('button, [role="button"], .wea-btn, .ant-btn'));
    return buttons.some(btn => (btn.innerText || btn.textContent || '').includes('保存'));
  });
  return hasSave;
}

async function saveForm(page) {
  const saveButton = page.getByRole('button', { name: /保\s*存/ }).first();
  if (await saveButton.count() === 0) {
    // Try a more flexible search
    const found = await page.evaluate(() => {
      const buttons = Array.from(document.querySelectorAll('button, [role="button"], .wea-btn, .ant-btn'));
      for (const btn of buttons) {
        const text = (btn.innerText || btn.textContent || '').trim();
        if (text === '保存') {
          btn.click();
          return true;
        }
      }
      return false;
    });
    if (found) {
      await page.waitForLoadState('domcontentloaded', { timeout: 15000 }).catch(() => undefined);
      await page.waitForTimeout(2500);
      return;
    }
    throw new Error('Save button was not found. Refusing to continue.');
  }
  await saveButton.click();
  await page.waitForLoadState('domcontentloaded', { timeout: 15000 }).catch(() => undefined);
  await page.waitForTimeout(2500);
}

function expectEqual(actual, expected, label, errors) {
  if (actual !== expected) {
    errors.push(`${label}: expected "${expected}", got "${actual}"`);
  }
}

function verifyForm(form, entry) {
  const errors = [];
  expectEqual(form.assignedDate, entry.date, 'assignedDate', errors);
  expectEqual(form.customer, CUSTOMER_NAME, 'customer', errors);
  expectEqual(form.paidTransform, PAID_TRANSFORM_NO_NAME, 'paidTransform', errors);
  expectEqual(form.attendance, entry.attendance, 'attendance', errors);
  expectEqual(form.overtime, entry.overtime, 'overtime', errors);
  expectEqual(form.total, entry.total, 'total', errors);
  expectEqual(form.detailTotal, entry.total, 'detailTotal', errors);
  expectEqual(form.module, MODULE_NAME, 'module', errors);
  expectEqual(form.duration, entry.total, 'duration', errors);
  expectEqual(form.serial, '', 'serial', errors);
  expectEqual(form.remark, '', 'remark', errors);
  return errors;
}

function buildPlannedForm(entry) {
  return {
    customer: CUSTOMER_NAME,
    paidTransform: PAID_TRANSFORM_NO_NAME,
    attendance: entry.attendance,
    overtime: entry.overtime,
    total: entry.total,
    detailTotal: entry.total,
    module: MODULE_NAME,
    duration: entry.total,
    serial: '',
    remark: '',
  };
}

function buildVerification(form, entry) {
  const errors = verifyForm(form, entry);
  return {
    matches: errors.length === 0,
    needsFill: errors.length > 0,
    errors,
  };
}

async function waitForVerifiedForm(page, entry, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  let lastErrors = [];

  while (Date.now() <= deadline) {
    const form = await readForm(page);
    lastErrors = verifyForm(form, entry);
    if (lastErrors.length === 0) {
      return form;
    }
    await page.waitForTimeout(500);
  }

  throw new Error(`Saved form did not match expectations for ${entry.date}: ${lastErrors.join('; ')}`);
}

async function run() {
  const options = parseArgs(process.argv.slice(2));
  const { chromium } = loadPlaywright();
  const browser = await chromium.connectOverCDP(options.cdpEndpoint);
  const context = browser.contexts()[0];
  if (!context) {
    throw new Error('No browser context is available from the CDP endpoint.');
  }

  let skipped = [];
  let entries = options.entries;
  if (options.autoFromList) {
    const autoPlan = await buildAutoEntriesFromList(context, options);
    skipped = autoPlan.skipped;
    entries = [...autoPlan.entries, ...options.entries];
  }

  const results = [];
  for (const entry of entries) {
    const page = await resolveFormPage(context, entry);
    const before = await readForm(page);
    const planned = buildPlannedForm(entry);
    const beforeVerification = buildVerification(before, entry);

    if (options.dryRun || options.verifyOnly) {
      results.push({
        date: entry.date,
        dryRun: options.dryRun,
        verifyOnly: options.verifyOnly,
        overtimeSource: entry.overtimeSource,
        current: sanitizePage(before),
        planned,
        verification: beforeVerification,
      });
      continue;
    }

    if (options.fillMissing && beforeVerification.matches) {
      results.push({
        date: entry.date,
        skipped: true,
        reason: 'already matches planned values',
        current: sanitizePage(before),
        planned,
        verification: beforeVerification,
      });
      continue;
    }

    // Check if this form has a save button first (not already submitted/read-only)
    const canSave = await hasSaveButton(page);
    if (!canSave) {
      skipped.push({
        date: entry.date,
        reason: 'save button not found, form may be already submitted or read-only',
      });
      results.push({
        date: entry.date,
        skipped: true,
        reason: 'save button not found, form may be already submitted or read-only',
        current: sanitizePage(before),
        planned,
        verification: beforeVerification,
      });
      continue;
    }

    await fillForm(page, entry);
    const filled = await readForm(page);
    const fillErrors = verifyForm(filled, entry);
    if (fillErrors.length > 0) {
      throw new Error(`Filled form did not match expectations for ${entry.date}: ${fillErrors.join('; ')}`);
    }

    try {
      await saveForm(page);
    } catch (saveError) {
      // If save fails specifically because no button found, skip this one
      const errorMsg = saveError instanceof Error ? saveError.message : String(saveError);
      if (errorMsg.includes('Save button was not found')) {
        skipped.push({
          date: entry.date,
          reason: 'save button not found during save attempt, form may be already submitted',
        });
        results.push({
          date: entry.date,
          skipped: true,
          reason: 'save button not found during save attempt, form may be already submitted',
          beforeFill: sanitizePage(before),
          afterFill: sanitizePage(filled),
        });
        continue;
      }
      throw saveError;
    }

    const saved = await waitForVerifiedForm(page, entry, 10000);

    results.push({
      date: entry.date,
      dryRun: options.dryRun,
      fillMissing: options.fillMissing,
      overtimeSource: entry.overtimeSource,
      before: sanitizePage(before),
      saved: sanitizePage(saved),
      verification: buildVerification(saved, entry),
    });
  }

  console.log(JSON.stringify({
    ok: true,
    dryRun: options.dryRun,
    verifyOnly: options.verifyOnly,
    fillMissing: options.fillMissing,
    skipped,
    results,
  }, null, 2));

  process.exit(0);
}

if (require.main === module) {
  run().catch((error) => {
    console.error(JSON.stringify({
      ok: false,
      error: error instanceof Error ? error.message : String(error),
    }, null, 2));
    process.exit(1);
  });
}

module.exports = {
  attendanceForDate,
  buildPlannedForm,
  buildVerification,
  formatHours,
  parseArgs,
  parseEntry,
  parseOvertimeEntry,
  verifyForm,
};
