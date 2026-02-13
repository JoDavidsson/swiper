#!/usr/bin/env node
/* eslint-disable no-console */
const path = require('path');

const functionsRoot = path.resolve(__dirname, '..', 'firebase', 'functions');
// eslint-disable-next-line import/no-dynamic-require, global-require
const admin = require(path.join(functionsRoot, 'node_modules', 'firebase-admin'));

const projectId = process.env.GCLOUD_PROJECT || 'swiper-95482';
const pollMs = Number(process.env.POLL_MS || '5000');
const runLimit = Number(process.env.RUN_LIMIT || '120');
const eventLimit = Number(process.env.EVENT_LIMIT || '400');
const sourceFilter = (process.env.SOURCE_ID || '').trim();
const summaryEvery = Number(process.env.SUMMARY_EVERY || '6');
const maxSeen = Number(process.env.MAX_SEEN || '5000');

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8180';
}

admin.initializeApp({ projectId });
const db = admin.firestore();

const seenRunState = new Map();
const seenJobState = new Map();
const seenEvents = new Set();

function toMs(value) {
  if (!value) return 0;
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (typeof value === 'number') return value;
  if (typeof value === 'string') return Date.parse(value) || 0;
  return 0;
}

function fmt(ms) {
  if (!ms) return 'unknown';
  return new Date(ms).toISOString().replace('T', ' ').replace('Z', 'Z');
}

function slimText(input, max = 120) {
  if (!input) return '';
  const s = String(input).replace(/\s+/g, ' ').trim();
  return s.length <= max ? s : `${s.slice(0, max - 1)}...`;
}

function rememberSet(set, id) {
  set.add(id);
  if (set.size <= maxSeen) return;
  const keep = Array.from(set).slice(-Math.floor(maxSeen * 0.8));
  set.clear();
  for (const x of keep) set.add(x);
}

function runStateKey(data) {
  const stats = data.stats || {};
  return JSON.stringify({
    status: data.status || '-',
    urlsDiscovered: stats.urlsDiscovered || 0,
    urlsCandidateProducts: stats.urlsCandidateProducts || 0,
    urlsExtracted: stats.urlsExtracted || 0,
    success: stats.success || 0,
    upserted: stats.upserted || 0,
    failed: stats.failed || 0,
    classified: stats.classified || 0,
    goldPromoted: stats.goldPromoted || 0,
    reviewQueued: stats.reviewQueued || 0,
  });
}

function jobStateKey(data) {
  return JSON.stringify({
    status: data.status || '-',
    jobType: data.jobType || '-',
    error: slimText(data.error || '', 80),
  });
}

function printRun(doc) {
  const data = doc.data() || {};
  const stats = data.stats || {};
  const startedMs = toMs(data.startedAt);
  const finishedMs = toMs(data.finishedAt);
  const pieces = [
    `[RUN ${fmt(startedMs)}]`,
    `source=${data.sourceId || '-'}`,
    `run=${doc.id}`,
    `status=${data.status || '-'}`,
    `discover=${stats.urlsDiscovered || 0}`,
    `candidates=${stats.urlsCandidateProducts || 0}`,
    `extracted=${stats.urlsExtracted || 0}`,
    `success=${stats.success || 0}`,
    `upserted=${stats.upserted || 0}`,
    `failed=${stats.failed || 0}`,
    `classified=${stats.classified || 0}`,
  ];
  if (finishedMs) pieces.push(`finished=${fmt(finishedMs)}`);
  if (data.errorSummary) pieces.push(`error=${slimText(data.errorSummary, 140)}`);
  console.log(pieces.join(' | '));
}

function printJob(doc) {
  const data = doc.data() || {};
  const updatedMs = toMs(data.updatedAt || data.createdAt);
  const pieces = [
    `[JOB ${fmt(updatedMs)}]`,
    `source=${data.sourceId || '-'}`,
    `run=${data.runId || '-'}`,
    `job=${data.jobType || '-'}`,
    `status=${data.status || '-'}`,
  ];
  if (data.error) pieces.push(`error=${slimText(data.error, 140)}`);
  console.log(pieces.join(' | '));
}

function printEvent(doc) {
  const data = doc.data() || {};
  const eventName = data.eventName || '-';
  const createdMs = toMs(data.createdAtServer || data.createdAtClient);
  const rank = data.rank && typeof data.rank === 'object' ? data.rank : {};
  const ext = data.ext && typeof data.ext === 'object' ? data.ext : {};
  const item = data.item && typeof data.item === 'object' ? data.item : {};
  const pieces = [
    `[EVT ${fmt(createdMs)}]`,
    `event=${eventName}`,
    `session=${data.sessionId || '-'}`,
  ];

  if (eventName === 'deck_response' || eventName === 'deck_render_snapshot') {
    pieces.push(`req=${rank.requestId || ext.requestId || '-'}`);
    pieces.push(`sameFamilyTop8=${rank.sameFamilyTop8Rate ?? '-'}`);
    pieces.push(`sourceConcTop8=${rank.sourceConcentrationTop8 ?? '-'}`);
    pieces.push(`sourceDivTop8=${rank.sourceDiversityTop8 ?? '-'}`);
    pieces.push(`variant=${rank.variant || '-'}`);
  }

  if (eventName === 'swipe_right' || eventName === 'swipe_left') {
    pieces.push(`item=${data.itemId || item.itemId || ext.itemId || ext.item_id || '-'}`);
    pieces.push(`pos=${item.positionInDeck ?? data.positionInDeck ?? ext.positionInDeck ?? '-'}`);
  }

  console.log(pieces.join(' | '));
}

async function pollRuns() {
  const snap = await db
    .collection('ingestionRuns')
    .orderBy('startedAt', 'desc')
    .limit(runLimit)
    .get();

  for (const doc of snap.docs) {
    const data = doc.data() || {};
    if (sourceFilter && data.sourceId !== sourceFilter) continue;
    const key = runStateKey(data);
    const prev = seenRunState.get(doc.id);
    if (prev === key) continue;
    printRun(doc);
    seenRunState.set(doc.id, key);
  }
}

async function pollJobs() {
  const snap = await db
    .collection('ingestionJobs')
    .orderBy('updatedAt', 'desc')
    .limit(runLimit)
    .get();

  for (const doc of snap.docs) {
    const data = doc.data() || {};
    if (sourceFilter && data.sourceId !== sourceFilter) continue;
    const key = jobStateKey(data);
    const prev = seenJobState.get(doc.id);
    if (prev === key) continue;
    printJob(doc);
    seenJobState.set(doc.id, key);
  }
}

async function pollEvents() {
  const snap = await db
    .collection('events_v1')
    .orderBy('createdAtServer', 'desc')
    .limit(eventLimit)
    .get();

  const fresh = [];
  for (const doc of snap.docs) {
    if (seenEvents.has(doc.id)) continue;
    const data = doc.data() || {};
    const eventName = data.eventName || '';
    const tracked =
      eventName === 'deck_response' ||
      eventName === 'deck_render_snapshot' ||
      eventName === 'swipe_right' ||
      eventName === 'swipe_left' ||
      eventName === 'outbound_click';
    if (!tracked) continue;
    fresh.push(doc);
  }

  fresh.reverse();
  for (const doc of fresh) {
    printEvent(doc);
    rememberSet(seenEvents, doc.id);
  }
}

async function printSummary() {
  const itemsSnap = await db.collection('items').where('isActive', '==', true).limit(20000).get();
  let classified = 0;
  const bySource = {};

  for (const doc of itemsSnap.docs) {
    const data = doc.data() || {};
    const c = data.classification && typeof data.classification === 'object' ? data.classification : null;
    if (c && c.primaryCategory) classified += 1;
    const sid = String(data.sourceId || 'unknown');
    bySource[sid] = (bySource[sid] || 0) + 1;
  }

  const topSources = Object.entries(bySource)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 8)
    .map(([k, v]) => `${k}:${v}`)
    .join(', ');

  console.log(
    `[SUMMARY ${fmt(Date.now())}] activeItems=${itemsSnap.size} classified=${classified} unclassified=${itemsSnap.size - classified}` +
      (topSources ? ` | topSources=${topSources}` : '')
  );
}

async function primeSeen() {
  const [runs, jobs, events] = await Promise.all([
    db.collection('ingestionRuns').orderBy('startedAt', 'desc').limit(runLimit).get(),
    db.collection('ingestionJobs').orderBy('updatedAt', 'desc').limit(runLimit).get(),
    db.collection('events_v1').orderBy('createdAtServer', 'desc').limit(eventLimit).get(),
  ]);

  for (const doc of runs.docs) {
    seenRunState.set(doc.id, runStateKey(doc.data() || {}));
  }
  for (const doc of jobs.docs) {
    seenJobState.set(doc.id, jobStateKey(doc.data() || {}));
  }
  for (const doc of events.docs) {
    rememberSet(seenEvents, doc.id);
  }
}

async function main() {
  console.log(
    `Listening pipeline observability (project=${projectId}${sourceFilter ? `, source=${sourceFilter}` : ''})`
  );
  console.log('Streams: ingestionRuns, ingestionJobs, events_v1 + periodic item/classification summary');
  console.log('Press Ctrl+C to stop.');

  await primeSeen();

  let tick = 0;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    await pollRuns();
    await pollJobs();
    await pollEvents();
    tick += 1;
    if (tick % summaryEvery === 0) {
      await printSummary();
    }
    await new Promise((resolve) => setTimeout(resolve, pollMs));
  }
}

main().catch((error) => {
  console.error('listen_pipeline_observability_failed', error);
  process.exit(1);
});
