import { assertEquals } from 'jsr:@std/assert@1';
import { extractText, extractTranslation } from './google.ts';

Deno.test('extractText returns trimmed full text', () => {
  const resp = { responses: [{ fullTextAnnotation: { text: ' नमस्कार\n' } }] };
  assertEquals(extractText(resp), 'नमस्कार');
});

Deno.test('extractText returns empty string when nothing found', () => {
  assertEquals(extractText({ responses: [{}] }), '');
  assertEquals(extractText({}), '');
});

Deno.test('extractTranslation returns translated text', () => {
  const resp = { data: { translations: [{ translatedText: 'Hello' }] } };
  assertEquals(extractTranslation(resp), 'Hello');
});

Deno.test('extractTranslation returns empty string on bad payload', () => {
  assertEquals(extractTranslation({}), '');
});
