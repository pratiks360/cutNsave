import { assertEquals } from 'jsr:@std/assert@1';
import { extractText } from './google.ts';

Deno.test('extractText returns trimmed full text', () => {
  const resp = { responses: [{ fullTextAnnotation: { text: ' नमस्कार\n' } }] };
  assertEquals(extractText(resp), 'नमस्कार');
});

Deno.test('extractText returns empty string when nothing found', () => {
  assertEquals(extractText({ responses: [{}] }), '');
  assertEquals(extractText({}), '');
});
