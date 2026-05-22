const corsHeaders = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'POST, OPTIONS',
  'access-control-allow-headers': 'authorization, content-type, x-mobilecode-provider',
  'access-control-max-age': '86400',
};

function jsonResponse(payload, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...corsHeaders,
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
    },
  });
}

function requireRelayAuth(request, env) {
  const token = (env.MOBILECODE_RELAY_TOKEN || '').trim();
  if (!token) return null;
  const authorization = request.headers.get('authorization') || '';
  const expected = `Bearer ${token}`;
  return authorization === expected ? null : jsonResponse({ error: 'Unauthorized relay request.' }, 401);
}

function normalizeBaseUrl(baseUrl) {
  return String(baseUrl || '').trim().replace(/\/+$/, '');
}

function anthropicMessagesUrl(baseUrl) {
  const normalized = normalizeBaseUrl(baseUrl);
  if (normalized.endsWith('/v1/messages') || normalized.endsWith('/messages')) return normalized;
  if (normalized.endsWith('/v1')) return `${normalized}/messages`;
  return `${normalized}/v1/messages`;
}

function openAiChatUrl(baseUrl) {
  const normalized = normalizeBaseUrl(baseUrl);
  if (normalized.endsWith('/chat/completions')) return normalized;
  return `${normalized}/chat/completions`;
}

function providerConfig(provider, env) {
  const normalizedProvider = String(provider || '').toLowerCase();
  if (normalizedProvider === 'mimo') {
    return {
      apiKey: env.MIMO_API_KEY,
      url: anthropicMessagesUrl(env.MIMO_BASE_URL || 'https://token-plan-cn.xiaomimimo.com/anthropic'),
      flavor: 'anthropic',
    };
  }
  if (normalizedProvider === 'deepseek' || normalizedProvider === 'deep_seek') {
    return {
      apiKey: env.DEEPSEEK_API_KEY,
      url: openAiChatUrl(env.DEEPSEEK_BASE_URL || 'https://api.deepseek.com'),
      flavor: 'openai',
    };
  }
  return null;
}

function upstreamHeaders(config) {
  const headers = {
    'content-type': 'application/json',
    'authorization': `Bearer ${config.apiKey}`,
  };
  if (config.flavor === 'anthropic') {
    headers['anthropic-version'] = '2023-06-01';
    headers['x-api-key'] = config.apiKey;
  }
  return headers;
}

function clampInt(value, fallback, min, max) {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(Math.max(parsed, min), max);
}

function compact(value, limit = 800) {
  const text = String(value || '').replace(/\s+/g, ' ').trim();
  if (text.length <= limit) return text;
  return `${text.slice(0, Math.max(0, limit - 1))}...`;
}

function isBlockedHost(hostname) {
  const host = String(hostname || '').toLowerCase();
  if (!host || host === 'localhost' || host.endsWith('.localhost') || host.endsWith('.local')) return true;
  if (/^(127\.|10\.|0\.)/.test(host)) return true;
  if (/^192\.168\./.test(host)) return true;
  if (/^169\.254\./.test(host)) return true;
  const match172 = host.match(/^172\.(\d+)\./);
  if (match172) {
    const second = Number.parseInt(match172[1], 10);
    if (second >= 16 && second <= 31) return true;
  }
  if (host === '::1' || host.startsWith('fc') || host.startsWith('fd') || host.startsWith('fe80')) return true;
  return false;
}

function safePublicHttpsUrl(rawUrl) {
  let parsed;
  try {
    parsed = new URL(String(rawUrl || '').trim());
  } catch (_) {
    return null;
  }
  if (parsed.protocol !== 'https:' || isBlockedHost(parsed.hostname)) return null;
  return parsed;
}

function stripHtml(html) {
  return compact(
    String(html || '')
      .replace(/<script[\s\S]*?<\/script>/gi, ' ')
      .replace(/<style[\s\S]*?<\/style>/gi, ' ')
      .replace(/<[^>]+>/g, ' ')
      .replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>'),
    12000,
  );
}

function titleFromHtml(html) {
  const match = String(html || '').match(/<title[^>]*>([\s\S]*?)<\/title>/i);
  return match ? compact(stripHtml(match[1]), 160) : '';
}

function compactResult(result, index) {
  return {
    refId: result.refId || `web_${index + 1}`,
    title: compact(result.title, 160),
    url: String(result.url || '').trim(),
    snippet: compact(result.snippet, 360),
  };
}

async function tavilySearch(query, count, env) {
  if (!env.TAVILY_API_KEY) return null;
  const response = await fetch('https://api.tavily.com/search', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      api_key: env.TAVILY_API_KEY,
      query,
      max_results: count,
      search_depth: 'basic',
      include_answer: false,
      include_raw_content: false,
    }),
  });
  if (!response.ok) throw new Error(`Tavily search failed: ${response.status}`);
  const body = await response.json();
  return (Array.isArray(body.results) ? body.results : [])
    .map((item, index) => compactResult({
      refId: `web_${index + 1}`,
      title: item.title,
      url: item.url,
      snippet: item.content,
    }, index));
}

async function bingSearch(query, count, env) {
  if (!env.BING_SEARCH_API_KEY) return null;
  const endpoint = env.BING_SEARCH_ENDPOINT || 'https://api.bing.microsoft.com/v7.0/search';
  const url = new URL(endpoint);
  url.searchParams.set('q', query);
  url.searchParams.set('count', String(count));
  url.searchParams.set('responseFilter', 'Webpages');
  const response = await fetch(url.toString(), {
    headers: { 'Ocp-Apim-Subscription-Key': env.BING_SEARCH_API_KEY },
  });
  if (!response.ok) throw new Error(`Bing search failed: ${response.status}`);
  const body = await response.json();
  const values = body.webPages && Array.isArray(body.webPages.value) ? body.webPages.value : [];
  return values.map((item, index) => compactResult({
    refId: `web_${index + 1}`,
    title: item.name,
    url: item.url,
    snippet: item.snippet,
  }, index));
}

async function duckDuckGoSearch(query, count) {
  const url = new URL('https://api.duckduckgo.com/');
  url.searchParams.set('q', query);
  url.searchParams.set('format', 'json');
  url.searchParams.set('no_html', '1');
  url.searchParams.set('no_redirect', '1');
  const response = await fetch(url.toString(), {
    headers: { 'user-agent': 'MobileCodeRelay/1.0' },
  });
  if (!response.ok) throw new Error(`DuckDuckGo search failed: ${response.status}`);
  const body = await response.json();
  const raw = [];
  if (body.AbstractURL || body.AbstractText) {
    raw.push({
      title: body.Heading || query,
      url: body.AbstractURL,
      snippet: body.AbstractText,
    });
  }
  const addTopics = (topics) => {
    if (!Array.isArray(topics)) return;
    for (const item of topics) {
      if (raw.length >= count) break;
      if (Array.isArray(item.Topics)) {
        addTopics(item.Topics);
        continue;
      }
      raw.push({
        title: item.Text,
        url: item.FirstURL,
        snippet: item.Text,
      });
    }
  };
  addTopics(body.Results);
  addTopics(body.RelatedTopics);
  return raw
    .filter((item) => item.url || item.snippet)
    .slice(0, count)
    .map((item, index) => compactResult({
      refId: `web_${index + 1}`,
      title: item.title,
      url: item.url,
      snippet: item.snippet,
    }, index));
}

async function handleWebSearch(input, env) {
  const query = compact(input.query, 240);
  if (!query) return jsonResponse({ error: 'web_search requires input.query.' }, 400);
  const count = clampInt(input.count, 5, 1, 5);
  let source = 'duckduckgo';
  let results = null;
  if (env.TAVILY_API_KEY) {
    source = 'tavily';
    results = await tavilySearch(query, count, env);
  } else if (env.BING_SEARCH_API_KEY) {
    source = 'bing';
    results = await bingSearch(query, count, env);
  }
  if (!results) {
    results = await duckDuckGoSearch(query, count);
  }
  return jsonResponse({
    success: true,
    query,
    source,
    results: results.slice(0, count),
  });
}

async function handleFetchUrl(input) {
  const parsed = safePublicHttpsUrl(input.url);
  if (!parsed) return jsonResponse({ error: 'fetch_url only allows public https URLs.' }, 400);
  const maxBytes = clampInt(input.maxBytes || input.max_bytes, 80 * 1024, 1024, 120 * 1024);
  const response = await fetch(parsed.toString(), {
    headers: { 'user-agent': 'MobileCodeRelay/1.0' },
    redirect: 'follow',
  });
  const contentType = response.headers.get('content-type') || '';
  const finalUrl = response.url || parsed.toString();
  if (!safePublicHttpsUrl(finalUrl)) {
    return jsonResponse({ error: 'fetch_url redirected to a non-public or non-https URL.', url: parsed.toString() }, 400);
  }
  if (!response.ok) {
    return jsonResponse({ error: `fetch_url upstream returned ${response.status}.`, url: parsed.toString() }, 502);
  }
  const raw = await response.text();
  const truncated = raw.length > maxBytes;
  const kept = raw.slice(0, maxBytes);
  const isHtml = contentType.includes('html') || /<html|<!doctype html/i.test(kept);
  const text = isHtml ? stripHtml(kept) : compact(kept, 12000);
  return jsonResponse({
    success: true,
    url: parsed.toString(),
    finalUrl,
    contentType,
    title: isHtml ? titleFromHtml(kept) : '',
    truncated,
    text: compact(text, 8000),
  });
}

async function handleToolRequest(toolName, request, env) {
  let envelope;
  try {
    envelope = await request.json();
  } catch (_) {
    return jsonResponse({ error: 'Invalid JSON tool envelope.' }, 400);
  }
  const input = envelope && typeof envelope.input === 'object' ? envelope.input : envelope;
  try {
    if (toolName === 'web_search') return await handleWebSearch(input || {}, env);
    if (toolName === 'fetch_url') return await handleFetchUrl(input || {});
  } catch (error) {
    return jsonResponse({ error: error && error.message ? error.message : String(error) }, 502);
  }
  return jsonResponse({ error: 'Unknown relay tool endpoint.' }, 404);
}

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders });
    }
    if (request.method !== 'POST') {
      return jsonResponse({ error: 'Use POST /v1/provider.' }, 405);
    }

    const authError = requireRelayAuth(request, env);
    if (authError) return authError;

    const url = new URL(request.url);
    if (url.pathname.startsWith('/v1/tools/')) {
      const toolName = url.pathname.substring('/v1/tools/'.length);
      return handleToolRequest(toolName, request, env);
    }
    if (url.pathname !== '/v1/provider') {
      return jsonResponse({ error: 'Unknown relay endpoint.' }, 404);
    }

    let envelope;
    try {
      envelope = await request.json();
    } catch (_) {
      return jsonResponse({ error: 'Invalid JSON relay envelope.' }, 400);
    }

    const config = providerConfig(envelope.provider, env);
    if (!config) {
      return jsonResponse({ error: `Unsupported provider: ${String(envelope.provider || '')}` }, 400);
    }
    if (!config.apiKey || !String(config.apiKey).trim()) {
      return jsonResponse({ error: `Relay provider key is not configured for ${String(envelope.provider || '')}.` }, 500);
    }
    if (!envelope.body || typeof envelope.body !== 'object') {
      return jsonResponse({ error: 'Relay envelope body must be an object.' }, 400);
    }

    const upstream = await fetch(config.url, {
      method: 'POST',
      headers: upstreamHeaders(config),
      body: JSON.stringify(envelope.body),
    });

    const headers = new Headers(corsHeaders);
    headers.set('cache-control', 'no-store');
    const contentType = upstream.headers.get('content-type');
    if (contentType) headers.set('content-type', contentType);

    return new Response(upstream.body, {
      status: upstream.status,
      statusText: upstream.statusText,
      headers,
    });
  },
};
