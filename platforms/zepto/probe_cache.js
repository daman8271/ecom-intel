const { execFile } = require('child_process');
const crypto = require('crypto');
const uuid = () => crypto.randomUUID();

const GW = 'https://bff-gateway.zeptonow.com';
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36';
const COMPAT = 'CONVENIENCE_FEE,RAIN_FEE,EXTERNAL_COUPONS,STANDSTILL,BUNDLE,MULTI_SELLER_ENABLED,PIP_V1,ROLLUPS,SCHEDULED_DELIVERY,SAMPLING_ENABLED,HOMEPAGE_V2,NEW_ETA_BANNER,SUPER_SAVER:1,PROMO_CASH:0,24X7_ENABLED_V1,HP_V4_FEED,NEW_ROLLUPS_ENABLED,PLP_ON_SEARCH,DYNAMIC_FILTERS,NEW_FEE_STRUCTURE,NEW_BILL_INFO,SUPERSTORE_V1,MARKETPLACE_REPLACEMENT';

function commonHeaders(lat, lon) {
  const sid = uuid(), did = uuid(), rid = uuid();
  return {
    'accept': 'application/json, text/plain, */*', 'accept-language': 'en-US,en;q=0.9',
    'app_sub_platform': 'WEB', 'app_version': '12.64.1', 'appversion': '12.64.1',
    'auth_revamp_flow': 'v2', 'compatible_components': COMPAT, 'content-type': 'application/json',
    'device_id': did, 'deviceid': did, 'marketplace_type': 'ZEPTO_NOW',
    'origin': 'https://www.zeptonow.com', 'platform': 'WEB', 'referer': 'https://www.zeptonow.com/',
    'request_id': rid, 'requestid': rid, 'session_id': sid, 'sessionid': sid,
    'tenant': 'ZEPTO', 'x-without-bearer': 'true', 'user-agent': UA,
    'x-latitude': String(lat), 'x-longitude': String(lon), 'latitude': String(lat), 'longitude': String(lon),
  };
}

function curl(args) {
  return new Promise((resolve) => {
    execFile('curl', args, { maxBuffer: 128 * 1024 * 1024, encoding: 'utf8' }, (err, stdout) => {
      resolve(stdout || '');
    });
  });
}

function hdrArgs(h) { const a = []; for (const [k, v] of Object.entries(h)) a.push('-H', `${k}: ${v}`); return a; }

async function run() {
  const lat = 19.0760; const lon = 72.8777; // Mumbai
  const url1 = `${GW}/serviceability-service/api/v1/serviceability?lat=${lat}&long=${lon}`;
  const args1 = ['-s', ...hdrArgs(commonHeaders(lat, lon)), url1];
  const r1 = await curl(args1);
  let storeId = null;
  try {
    const data1 = JSON.parse(r1);
    storeId = data1.data.stores[0].storeId;
    console.log("Got storeId:", storeId);
  } catch (e) {
    console.log("Failed to parse store ID. Response was:", r1);
    return;
  }
  
  const h2 = commonHeaders(lat, lon);
  h2['store_id'] = storeId; h2['store_ids'] = storeId; h2['storeid'] = storeId; h2['store_etas'] = `{"${storeId}":10}`;
  const url2 = `${GW}/user-search-service/api/v3/search`;
  const body2 = JSON.stringify({ query: 'jivo', pageNumber: 0, intentId: uuid(), mode: 'AUTOSUGGEST', userSessionId: uuid() });
  
  const args2 = ['-s', '-i', '-X', 'POST', ...hdrArgs(h2), '--data', body2, url2];
  
  console.log("Fetching Request 1...");
  const r2 = await curl(args2);
  const parts = r2.split('\r\n\r\n');
  console.log("--- HEADERS 1 ---");
  const h2Str = parts[0].split('\n').filter(l => /^(x-cache|cache-control|age|x-kong-upstream-latency):/i.test(l)).join('\n');
  console.log(h2Str || parts[0]);
  
  console.log("\nFetching Request 2 (checking cache)...");
  const r3 = await curl(args2);
  const parts3 = r3.split('\r\n\r\n');
  console.log("--- HEADERS 2 ---");
  const h3Str = parts3[0].split('\n').filter(l => /^(x-cache|cache-control|age|x-kong-upstream-latency):/i.test(l)).join('\n');
  console.log(h3Str || parts3[0]);
}
run();
