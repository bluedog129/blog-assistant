import vm from 'node:vm';
import fs from 'node:fs';
import assert from 'node:assert/strict';
let pending = '11111111-1111-1111-1111-111111111111';
const tabs = [];
const callbacks = {};
const context = vm.createContext({
  AbortSignal,
  chrome: {
    action: { onClicked: { addListener() {} } },
    runtime: { getURL: path => `chrome-extension://test/${path}`, onMessage: { addListener() {} }, onInstalled: { addListener() {} }, onStartup: { addListener() {} } },
    storage: { local: { get: async () => ({ appBridgeToken: 'secret' }) } },
    alarms: { create: async () => {}, onAlarm: { addListener: fn => { callbacks.alarm = fn; } } },
    tabs: { query: async () => tabs, create: async tab => { tabs.push(tab); }, onUpdated: { addListener() {} } }
  },
  fetch: async (url, options) => {
    assert.equal(url, 'http://127.0.0.1:48765/pending');
    assert.equal(options.headers['X-Blog-Assistant-Token'], 'secret');
    return { ok: true, json: async () => ({ jobID: pending }) };
  }
});
vm.runInContext(fs.readFileSync('chrome-extension/background.js', 'utf8'), context);
await new Promise(resolve => setImmediate(resolve));
assert.equal(tabs.length, 1);
await vm.runInContext('checkPendingJob()', context);
assert.equal(tabs.length, 1, 'Repeated polling must not open duplicate tabs');
pending = null;
await vm.runInContext('checkPendingJob()', context);
assert.equal(tabs.length, 1);
pending = 'invalid';
await vm.runInContext('checkPendingJob()', context);
assert.equal(tabs.length, 1);
console.log('Passed authenticated pending-job detection and duplicate/invalid job protection');
