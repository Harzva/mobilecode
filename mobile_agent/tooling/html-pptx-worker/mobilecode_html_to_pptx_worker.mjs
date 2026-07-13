#!/usr/bin/env node

import http from 'node:http';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {chromium} from 'playwright';
import pptxgen from 'pptxgenjs';

const protocolVersion = 'mobilecode.html-render.v1';
const maxBodyBytes = 8 * 1024 * 1024;
const artifacts = new Map();
const args = parseArgs(process.argv.slice(2));
const host = args.host ?? process.env.MOBILECODE_PPTX_WORKER_HOST ?? '127.0.0.1';
const port = Number(args.port ?? process.env.MOBILECODE_PPTX_WORKER_PORT ?? 8792);
const publicBaseUrl = (
  args['public-base-url'] ??
  process.env.MOBILECODE_PPTX_WORKER_PUBLIC_BASE_URL ??
  `http://127.0.0.1:${port}`
).replace(/\/$/, '');
const token = args.token ?? process.env.MOBILECODE_PPTX_WORKER_TOKEN ?? '';
const chromePath = args['chrome-path'] ?? process.env.MOBILECODE_PPTX_CHROME_PATH ?? '';
const sourceRoot = path.resolve(
  args['source-root'] ??
  process.env.MOBILECODE_PPTX_WORKER_SOURCE_ROOT ??
  process.cwd(),
);
const artifactRoot = path.resolve(
  args['artifact-root'] ??
  process.env.MOBILECODE_PPTX_WORKER_ARTIFACT_ROOT ??
  path.join(process.cwd(), '.mobilecode-pptx-artifacts'),
);

await fs.mkdir(artifactRoot, {recursive: true});

const server = http.createServer(async (request, response) => {
  try {
    if (!authorized(request)) {
      return json(response, 401, {success: false, error: 'auth_failed'});
    }
    const url = new URL(request.url ?? '/', `http://${request.headers.host ?? 'localhost'}`);
    const artifactMatch = url.pathname.match(/^\/v1\/render\/artifacts\/([a-f0-9-]+)$/);
    if (request.method === 'GET' && artifactMatch) {
      return await serveArtifact(response, artifactMatch[1]);
    }
    if (request.method !== 'POST' || url.pathname !== '/v1/render/pptx') {
      return json(response, 404, {success: false, error: 'not_found'});
    }
    const payload = JSON.parse((await readBody(request)).toString('utf8'));
    const result = await renderPptx(payload);
    return json(response, 200, result);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return json(response, 400, {success: false, error: message});
  }
});

server.listen(port, host, () => {
  console.log(`MobileCode HTML-to-PPTX worker listening on http://${host}:${port}`);
  console.log(`Source root: ${sourceRoot}`);
});

async function renderPptx(payload) {
  if (payload?.protocolVersion !== protocolVersion) {
    throw new Error('unsupported protocolVersion');
  }
  if (payload?.engine !== 'html_pptx') {
    throw new Error('engine must be html_pptx');
  }
  const request = payload.request;
  if (!request || request.format !== 'pptx') {
    throw new Error('request.format must be pptx');
  }
  if ((request.pptxMode ?? 'visual') !== 'visual') {
    throw new Error('pptxMode=editableText is not implemented; use visual mode for now');
  }

  const dimensions = slideDimensions(request.slideAspectRatio ?? '16:9');
  const slideWidth = boundedInt(request.width, dimensions.pxWidth, 480, 4096);
  const slideHeight = boundedInt(request.height, dimensions.pxHeight, 480, 4096);
  const timeoutMs = boundedInt(request.timeoutMs, 120000, 5000, 900000);
  const project = await fs.mkdtemp(path.join(artifactRoot, 'render-'));
  const source = await materializeSource(request, project);
  const browser = await chromium.launch({
    headless: true,
    ...(chromePath ? {executablePath: chromePath} : {}),
  });
  const page = await browser.newPage({viewport: {width: slideWidth, height: slideHeight}, deviceScaleFactor: 1});
  const outputDir = path.join(project, 'slides');
  await fs.mkdir(outputDir, {recursive: true});
  try {
    await page.goto(source, {waitUntil: 'networkidle', timeout: timeoutMs});
    const slideCount = boundedInt(
      request.slideCount,
      await detectSlideCount(page),
      1,
      200,
    );
    const images = [];
    for (let index = 1; index <= slideCount; index += 1) {
      await page.goto(slideUrl(source, index), {waitUntil: 'networkidle', timeout: timeoutMs});
      await page.waitForTimeout(250);
      const imagePath = path.join(outputDir, `slide-${String(index).padStart(3, '0')}.png`);
      await page.screenshot({path: imagePath, type: 'png'});
      images.push(imagePath);
    }

    const outputPath = path.join(project, 'presentation.pptx');
    const pptx = new pptxgen();
    pptx.author = 'MobileCode';
    pptx.subject = 'HTML presentation export';
    pptx.title = request.suggestedName ?? 'MobileCode presentation';
    pptx.company = 'MobileCode';
    pptx.lang = 'zh-CN';
    pptx.defineLayout({name: 'MOBILECODE', width: dimensions.inchesWidth, height: dimensions.inchesHeight});
    pptx.layout = 'MOBILECODE';
    for (const imagePath of images) {
      const slide = pptx.addSlide();
      slide.background = {color: 'FFFFFF'};
      slide.addImage({path: imagePath, x: 0, y: 0, w: dimensions.inchesWidth, h: dimensions.inchesHeight});
    }
    await pptx.writeFile({fileName: outputPath});
    const stat = await fs.stat(outputPath);
    const artifactId = crypto.randomUUID();
    artifacts.set(artifactId, {path: outputPath, createdAt: Date.now()});
    return {
      success: true,
      protocolVersion,
      format: 'pptx',
      mimeType: 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      backend: 'html_pptx_playwright_pptxgenjs',
      artifactUrl: `${publicBaseUrl}/v1/render/artifacts/${artifactId}`,
      bytes: stat.size,
      width: slideWidth,
      height: slideHeight,
      metadata: {
        slideCount: images.length,
        slideAspectRatio: request.slideAspectRatio ?? '16:9',
        pptxMode: 'visual',
        source: 'html_pptx_worker',
      },
    };
  } finally {
    await browser.close();
  }
}

async function materializeSource(request, project) {
  if (typeof request.inlineHtml === 'string' && request.inlineHtml.trim()) {
    const filePath = path.join(project, 'index.html');
    await fs.writeFile(filePath, request.inlineHtml, 'utf8');
    return pathToFileURL(filePath).href;
  }
  if (typeof request.sourcePath === 'string' && request.sourcePath.trim()) {
    const candidate = path.resolve(request.sourcePath);
    assertInside(candidate, sourceRoot, 'sourcePath');
    const stat = await fs.stat(candidate);
    if (stat.isDirectory()) {
      const target = path.join(project, 'deck');
      await fs.cp(candidate, target, {recursive: true});
      const indexPath = path.join(target, 'index.html');
      await fs.access(indexPath);
      return pathToFileURL(indexPath).href;
    }
    const target = path.join(project, path.basename(candidate));
    await fs.copyFile(candidate, target);
    return pathToFileURL(target).href;
  }
  const sourceUrl = String(request.url ?? '').trim();
  if (!sourceUrl) {
    throw new Error('provide inlineHtml, sourcePath, or url');
  }
  const parsed = new URL(sourceUrl);
  if (!['file:', 'http:', 'https:'].includes(parsed.protocol)) {
    throw new Error('url must use file, http, or https');
  }
  return sourceUrl;
}

async function detectSlideCount(page) {
  return page.evaluate(() => {
    const candidates = [
      document.querySelectorAll('.slide').length,
      document.querySelectorAll('[data-slide]').length,
      document.querySelectorAll('[data-composition-id]').length,
    ];
    return Math.max(...candidates, 1);
  });
}

function slideUrl(source, index) {
  const url = new URL(source);
  url.hash = `/${index}`;
  return url.href;
}

function slideDimensions(ratio) {
  switch (ratio) {
    case '4:3':
      return {pxWidth: 1600, pxHeight: 1200, inchesWidth: 10, inchesHeight: 7.5};
    case '3:4':
      return {pxWidth: 900, pxHeight: 1200, inchesWidth: 7.5, inchesHeight: 10};
    case '1:1':
      return {pxWidth: 1200, pxHeight: 1200, inchesWidth: 10, inchesHeight: 10};
    case '16:9':
    default:
      return {pxWidth: 1920, pxHeight: 1080, inchesWidth: 13.333333, inchesHeight: 7.5};
  }
}

function authorized(request) {
  return !token || request.headers.authorization === `Bearer ${token}`;
}

function assertInside(candidate, root, label) {
  const relative = path.relative(root, candidate);
  if (relative.startsWith('..') || path.isAbsolute(relative)) {
    throw new Error(`${label} is outside the configured worker root`);
  }
}

function boundedInt(value, fallback, lower, upper) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.max(lower, Math.min(upper, Math.trunc(number)));
}

async function readBody(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > maxBodyBytes) throw new Error('request body exceeds the configured limit');
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

async function serveArtifact(response, artifactId) {
  const artifact = artifacts.get(artifactId);
  if (!artifact) return json(response, 404, {success: false, error: 'artifact_not_found'});
  try {
    const data = await fs.readFile(artifact.path);
    response.writeHead(200, {
      'Content-Type': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'Content-Length': data.length,
    });
    response.end(data);
  } catch {
    artifacts.delete(artifactId);
    return json(response, 404, {success: false, error: 'artifact_not_found'});
  }
}

function json(response, status, payload) {
  const body = Buffer.from(JSON.stringify(payload));
  response.writeHead(status, {'Content-Type': 'application/json', 'Content-Length': body.length});
  response.end(body);
}

function parseArgs(values) {
  const parsed = {};
  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (!value.startsWith('--')) continue;
    const key = value.slice(2);
    parsed[key] = values[index + 1]?.startsWith('--') ? true : values[++index];
  }
  return parsed;
}
