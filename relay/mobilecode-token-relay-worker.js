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
      url: openAiChatUrl(env.DEEPSEEK_BASE_URL || 'https://api.deepseek.com/v1'),
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
