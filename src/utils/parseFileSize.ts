
export default function parseFileSize(size?: number) {
  if (!size) return '-';

  const kb = size / 1024;
  if (kb > 1_000_000) return `${Math.round(kb / 1_048_576 * 10) / 10} GB`;
  if (kb > 1000) return `${Math.round(kb / 1024 * 10) / 10} MB`;
  return `${Math.round(kb * 10) / 10} KB`;
}
