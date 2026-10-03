import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

export const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

export const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });

// Runs consume_quota as the caller (JWT forwarded), so membership is enforced in SQL.
export async function consume(
  req: Request,
  libraryId: string,
  kind: 'ocr' | 'translate',
  amount: number,
): Promise<'ok' | 'quota' | 'forbidden'> {
  const client = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } } },
  );
  const { data, error } = await client.rpc('consume_quota', {
    lib: libraryId,
    kind,
    amount,
  });
  if (error) return 'forbidden';
  return data ? 'ok' : 'quota';
}
