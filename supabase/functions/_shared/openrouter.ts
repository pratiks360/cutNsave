// deno-lint-ignore-file no-explicit-any
// Free-tier OpenRouter translation, same pattern as other projects' OpenRouter
// usage: every candidate model is filtered to ":free" slugs (or the
// 'openrouter/free' auto-router alias) so this never spends real money, and a
// batch tries models in order, falling through to the next on any failure
// instead of giving up on the first model that's rate-limited or down.

const OPENROUTER_BASE = 'https://openrouter.ai/api/v1';
const OPENROUTER_MODELS_URL = `${OPENROUTER_BASE}/models`;

// Last-resort pool if the live /models fetch fails or returns nothing -- kept
// short and deliberately not exhaustive; the live fetch is the real source of
// truth for which :free models currently exist.
const FALLBACK_MODELS = [
  'google/gemini-2.0-flash-exp:free',
  'meta-llama/llama-3.3-70b-instruct:free',
  'openrouter/free',
];

export const isFreeModel = (m: string | undefined | null): m is string =>
  !!m && (m === 'openrouter/free' || m.endsWith(':free'));

let liveFreeModelsCache: { at: number; models: string[] } | null = null;
const LIVE_MODELS_TTL_MS = 60 * 60 * 1000;

// Test-only: the live-model pool is cached across warm invocations in
// production (so a translate burst doesn't hammer /models), but that same
// caching would leak a mocked response from one test into the next.
export function resetLiveModelsCacheForTesting() {
  liveFreeModelsCache = null;
}

async function fetchLiveFreeModels(): Promise<string[]> {
  if (liveFreeModelsCache && Date.now() - liveFreeModelsCache.at < LIVE_MODELS_TTL_MS) {
    return liveFreeModelsCache.models;
  }
  try {
    const res = await fetch(OPENROUTER_MODELS_URL, { headers: { 'Content-Type': 'application/json' } });
    if (!res.ok) return liveFreeModelsCache?.models ?? [];
    const data = await res.json();
    const models: string[] = (data?.data ?? [])
      .map((m: any) => m?.id as string | undefined)
      .filter(isFreeModel);
    if (models.length > 0) liveFreeModelsCache = { at: Date.now(), models };
    return models;
  } catch {
    return liveFreeModelsCache?.models ?? [];
  }
}

async function resolveModels(): Promise<string[]> {
  const live = await fetchLiveFreeModels();
  return [...new Set([...live, ...FALLBACK_MODELS])].slice(0, 8);
}

const LANG_NAMES: Record<string, string> = { mr: 'Marathi', hi: 'Hindi', en: 'English' };

// Returns the translated text, or throws if every model in the pool failed.
export async function translateViaOpenRouter(
  text: string,
  sourceLang: string,
  apiKey: string,
): Promise<string> {
  const source = LANG_NAMES[sourceLang] ?? sourceLang;
  const models = await resolveModels();
  if (models.length === 0) throw new Error('no free model available');

  const system =
    'You are a translation engine. Translate the user\'s text from ' +
    source +
    ' to English. Respond with ONLY the translated text, no commentary, no quotes, ' +
    'no explanation, and no preserved source-language text.';

  let lastErr = '';
  for (const model of models) {
    try {
      const res = await fetch(`${OPENROUTER_BASE}/chat/completions`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${apiKey}`,
          'HTTP-Referer': 'https://github.com/pratiks360/cutNsave',
          'X-Title': 'cutNsave translate',
        },
        body: JSON.stringify({
          model,
          temperature: 0,
          max_tokens: 4000,
          messages: [
            { role: 'system', content: system },
            { role: 'user', content: text },
          ],
        }),
      });
      if (!res.ok) {
        lastErr = `${model} -> ${res.status}`;
        continue;
      }
      const data = await res.json();
      const translated = (data?.choices?.[0]?.message?.content ?? '').trim();
      if (translated) return translated;
      lastErr = `${model}: empty response`;
    } catch (e) {
      lastErr = `${model}: ${(e as Error).message}`;
    }
  }
  throw new Error(`all models failed; last error: ${lastErr}`);
}
