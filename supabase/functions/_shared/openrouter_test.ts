import { assertEquals, assertRejects } from 'jsr:@std/assert@1';
import { isFreeModel, resetLiveModelsCacheForTesting, translateViaOpenRouter } from './openrouter.ts';

Deno.test('isFreeModel accepts :free slugs and the auto-router alias', () => {
  assertEquals(isFreeModel('google/gemini-2.0-flash-exp:free'), true);
  assertEquals(isFreeModel('openrouter/free'), true);
  assertEquals(isFreeModel('openai/gpt-4o'), false);
  assertEquals(isFreeModel(undefined), false);
  assertEquals(isFreeModel(null), false);
});

function stubFetch(handler: (url: string) => Response) {
  const original = globalThis.fetch;
  globalThis.fetch = ((input: string | URL | Request) => {
    const url = typeof input === 'string' ? input : input.toString();
    return Promise.resolve(handler(url));
  }) as typeof fetch;
  return () => {
    globalThis.fetch = original;
  };
}

Deno.test('translateViaOpenRouter returns the first model that succeeds', async () => {
  resetLiveModelsCacheForTesting();
  const restore = stubFetch((url) => {
    if (url.endsWith('/models')) {
      return new Response(
        JSON.stringify({ data: [{ id: 'some/model:free' }, { id: 'paid/model' }] }),
        { status: 200 },
      );
    }
    return new Response(
      JSON.stringify({ choices: [{ message: { content: 'Hello there' } }] }),
      { status: 200 },
    );
  });
  try {
    const text = await translateViaOpenRouter('नमस्कार', 'mr', 'test-key');
    assertEquals(text, 'Hello there');
  } finally {
    restore();
  }
});

Deno.test('translateViaOpenRouter falls through to the next model on failure', async () => {
  let calls = 0;
  resetLiveModelsCacheForTesting();
  const restore = stubFetch((url) => {
    if (url.endsWith('/models')) {
      return new Response(
        JSON.stringify({ data: [{ id: 'flaky/model:free' }, { id: 'ok/model:free' }] }),
        { status: 200 },
      );
    }
    calls++;
    if (calls === 1) return new Response('rate limited', { status: 429 });
    return new Response(JSON.stringify({ choices: [{ message: { content: 'Second try' } }] }), {
      status: 200,
    });
  });
  try {
    const text = await translateViaOpenRouter('text', 'hi', 'test-key');
    assertEquals(text, 'Second try');
    assertEquals(calls, 2);
  } finally {
    restore();
  }
});

Deno.test('translateViaOpenRouter throws when every model fails', async () => {
  resetLiveModelsCacheForTesting();
  const restore = stubFetch((url) => {
    if (url.endsWith('/models')) {
      return new Response(JSON.stringify({ data: [{ id: 'only/model:free' }] }), { status: 200 });
    }
    return new Response('down', { status: 500 });
  });
  try {
    await assertRejects(() => translateViaOpenRouter('text', 'mr', 'test-key'));
  } finally {
    restore();
  }
});
