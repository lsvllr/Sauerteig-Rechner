/* Symbole des Rechners (gleicher Strich wie die Icons der Haushalt-App, shell/icons.generated.ts). */
const PFADE: Record<string, string> = {
  check: '<path d="M5 12.6 9.6 17 19 7"/>',
  chevron: '<path d="m6 9.5 6 6 6-6"/>',
  trash:
    '<path d="M4.5 6.5h15"/><path d="M9.5 6.5V4.8h5v1.7"/><path d="M6.5 6.5 7.4 20h9.2l.9-13.5"/><path d="M10.5 10v6"/><path d="M13.5 10v6"/>',
  disk: '<path d="M5 4h11.2L19.5 7.3V20H5z"/><path d="M8.5 4v4.6h6.5V4"/><rect x="8.5" y="13" width="7" height="7"/>',
};

export function Symbol({ name, size = 20 }: { name: keyof typeof PFADE; size?: number }) {
  return (
    <svg
      className="sf"
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.7"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      dangerouslySetInnerHTML={{ __html: PFADE[name] ?? '' }}
    />
  );
}
