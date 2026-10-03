// deno-lint-ignore-file no-explicit-any
export function extractText(resp: any): string {
  return (resp?.responses?.[0]?.fullTextAnnotation?.text ?? '').trim();
}
