import { createSignal } from 'solid-js';

export const fileData = new Map<string, FileType>();

type FileProcessMode = 'image' | 'video' | 'dir';

interface FileStateType {
  mode: FileProcessMode[];
  paths: string[];
  data: Map<string, FileType>;
  totalSize: number;
}

export const defaultStatus = {
  paths: [],
  mode: [],
  data: new Map(),
  totalSize: 0,
} as FileStateType;

const [state, setState] = createSignal(defaultStatus);

export default state;

function loop(files: InnerFileType[], callback?: (file: InnerFileType) => void) {
  files.forEach((file) => {
    loop(file.files, callback);
    callback?.(file);
  });
}

function collectPath(files: InnerFileType[]) {
  return files.map((item) => item.path);
}

export function setFileData(files: InnerFileType[]) {
  const data = new Map<string, FileType>();
  let mode = [] as FileProcessMode[];
  let totalSize = 0;

  loop(files, (file) => {
    totalSize += file.size;
    data.set(file.path, { ...file, files: collectPath(file.files) });

    if (mode.length === 3) return;
    if (file.mime_type === 'dir' && !mode.includes('dir')) {
      return mode.push('dir');
    }
    if (file.mime_type.includes('pdf')) {
      return mode.push('image');
    }
    if (file.mime_type.startsWith('image') && !mode.includes('image')) {
      return mode.push('image');
    }
    if (file.mime_type.startsWith('video') && !mode.includes('video')) {
      return mode.push('video');
    }
  });

  setState({ paths: collectPath(files), mode, totalSize, data });
}

export function reset() {
  setState(defaultStatus);
}
