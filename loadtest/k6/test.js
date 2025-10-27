import http from 'k6/http';
import { check, sleep } from 'k6';
import { SharedArray } from 'k6/data';

// Load endpoints configuration once per VU
// Tries ENV path first, then local repo default, then container/K8s mount path
const endpointsConfig = new SharedArray('endpoints-config', () => {
    const envPath = __ENV.ENDPOINTS_FILE || '';
    let raw;
    try {
        raw = open(envPath || '../config/endpoints.json');
    } catch (e1) {
        raw = open('/config/endpoints.json');
    }
    const parsed = JSON.parse(raw);
    return [parsed];
})[0];

const endpoints = endpointsConfig.endpoints || [];
const sequence = endpointsConfig.sequence || [];
const baseUrl = (__ENV.BASE_URL && __ENV.BASE_URL.trim()) || endpointsConfig.baseUrl || '';

// k6 options configurable via env
const vus = parseInt(__ENV.VUS || '10', 10);
const duration = __ENV.DURATION || '30s';
const stagesJson = __ENV.STAGES_JSON || '';
const sleepSeconds = parseFloat(__ENV.SLEEP || '1');
const stepSleepSeconds = parseFloat(__ENV.STEP_SLEEP || '0');
const thresholdP95 = __ENV.P95 || '800'; // ms
const sequenceOnce = (`${__ENV.SEQUENCE_ONCE || 'false'}`).toLowerCase() === 'true';

// Track per-VU whether the ordered sequence has already been executed
let sequenceHasRun = false;

export const options = stagesJson ? { stages: JSON.parse(stagesJson), thresholds: { http_req_duration: [`p(95)<${thresholdP95}`] } } : { vus, duration, thresholds: { http_req_duration: [`p(95)<${thresholdP95}`] } };

function resolveUrl(step) {
    if (step.url && step.url.startsWith('http')) {
        return step.url;
    }
    const path = step.path || '/';
    return `${baseUrl}${path}`;
}

function ensureHeadersObject(headers) {
    const h = headers || {};
    return h;
}

function toRequestBody(body, headers) {
    if (body === null || body === undefined) return null;
    if (typeof body === 'string') return body;
    const contentType = (headers && (headers['Content-Type'] || headers['content-type'])) || '';
    if (contentType.includes('application/json') || !contentType) {
        // Set default Content-Type to application/json when sending an object
        if (!contentType) {
            headers['Content-Type'] = 'application/json';
        }
        return JSON.stringify(body);
    }
    return body;
}

function pickEndpoint() {
    if (endpoints.length === 0) {
        return null;
    }
    const index = Math.floor(Math.random() * endpoints.length);
    return endpoints[index];
}

export default function() {
    if (sequence.length > 0) {
        if (sequenceOnce && sequenceHasRun) {
            if (sleepSeconds > 0) sleep(sleepSeconds);
            return;
        }
        for (const step of sequence) {
            const method = (step.method || 'GET').toUpperCase();
            const url = resolveUrl(step);
            const headers = ensureHeadersObject(step.headers);
            const body = toRequestBody(step.body, headers);

            console.log(`Sending request to ${url} with method ${method} and body ${body} and headers ${headers} `);
            const res = http.request(method, url, body, { headers });
            check(res, {
                'status is OK-ish (2xx/3xx)': (r) => r.status >= 200 && r.status < 400,
            });

            if (stepSleepSeconds > 0) sleep(stepSleepSeconds);
        }
        sequenceHasRun = true;
        if (sleepSeconds > 0) sleep(sleepSeconds);
        return;
    }

    const endpoint = pickEndpoint();
    if (!endpoint) {
        sleep(1);
        return;
    }

    const method = (endpoint.method || 'GET').toUpperCase();
    const url = resolveUrl(endpoint);
    const headers = ensureHeadersObject(endpoint.headers);
    const body = toRequestBody(endpoint.body || null, headers);
    const expected = endpoint.expectStatus || 200;

    const res = http.request(method, url, body, { headers });

    check(res, {
        'status is expected': (r) => Array.isArray(expected) ? expected.includes(r.status) : r.status === expected || (expected === 200 && r.status >= 200 && r.status < 300),
    });

    sleep(sleepSeconds);
}