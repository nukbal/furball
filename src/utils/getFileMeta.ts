import { invoke } from '@tauri-apps/api/tauri';

export default async function getFileMeta(paths: string[]) {
  const res = await invoke<string>('file_meta', { paths });
  return JSON.parse(res) as InnerFileType[];
}
