import { consume, cors, json } from '../_shared/auth.ts';
import { extractTranslation } from '../_shared/google.ts';

const MAX_CHARS = 30000;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const { text, source, library_id } = await req.json();
  if (!text || !source || !library_id) return json({ error: 'bad_request' }, 400);
  if (text.length > MAX_CHARS) return json({ error: 'too_long' }, 413);

  const gate = await consume(req, library_id, 'translate', text.length);
  if (gate !== 'ok') return json({ error: gate }, gate === 'quota' ? 429 : 403);

  const res = await fetch(
    `https://translation.googleapis.com/language/translate/v2?key=${Deno.env.get('GOOGLE_API_KEY')}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ q: text, source, target: 'en', format: 'text' }),
    },
  );
  if (!res.ok) return json({ error: 'upstream' }, 502);
  return json({ text: extractTranslation(await res.json()) });
});
