import { consume, cors, json } from '../_shared/auth.ts';
import { translateViaOpenRouter } from '../_shared/openrouter.ts';

const MAX_CHARS = 30000;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  let body: { text?: string; source?: string; library_id?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'bad_request' }, 400);
  }
  const { text, source, library_id } = body;
  if (!text || !source || !library_id) return json({ error: 'bad_request' }, 400);
  if (text.length > MAX_CHARS) return json({ error: 'too_long' }, 413);

  const gate = await consume(req, library_id, 'translate', text.length);
  if (gate !== 'ok') return json({ error: gate }, gate === 'quota' ? 429 : 403);

  const apiKey = Deno.env.get('OPENROUTER_API_KEY');
  if (!apiKey) return json({ error: 'server_not_configured' }, 500);

  try {
    const translated = await translateViaOpenRouter(text, source, apiKey);
    return json({ text: translated });
  } catch (e) {
    console.error('translate: all OpenRouter models failed:', (e as Error).message);
    return json({ error: 'upstream' }, 502);
  }
});
