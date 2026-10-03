import { consume, cors, json } from '../_shared/auth.ts';
import { extractText } from '../_shared/google.ts';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  let body: { image_base64?: string; library_id?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'bad_request' }, 400);
  }
  const { image_base64, library_id } = body;
  if (!image_base64 || !library_id) return json({ error: 'bad_request' }, 400);

  const gate = await consume(req, library_id, 'ocr', 1);
  if (gate !== 'ok') return json({ error: gate }, gate === 'quota' ? 429 : 403);

  const res = await fetch(
    `https://vision.googleapis.com/v1/images:annotate?key=${Deno.env.get('GOOGLE_API_KEY')}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        requests: [{
          image: { content: image_base64 },
          features: [{ type: 'DOCUMENT_TEXT_DETECTION' }],
          imageContext: { languageHints: ['mr', 'hi', 'en'] },
        }],
      }),
    },
  );
  if (!res.ok) return json({ error: 'upstream' }, 502);
  return json({ text: extractText(await res.json()) });
});
