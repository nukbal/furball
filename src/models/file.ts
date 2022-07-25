import { useCallback } from 'react';
import create, { type StateSelector, type EqualityChecker } from 'zustand';
import { subscribeWithSelector } from 'zustand/middleware';

const fileData = new Map<string, FileType>();

type FileProcessMode = 'image' | 'video' | 'dir';

interface FileStateType {
  mode: FileProcessMode[];
  status: StatusType;
  paths: string[];
  totalSize: number;
}
export const defaultStatus = { status: 'cancel', paths: [], mode: [], totalSize: 0 } as FileStateType;
const useState = create(subscribeWithSelector<FileStateType>(() => defaultStatus));

export default useState;
export function useFile<T>(
  selector: StateSelector<FileStateType & { data: Map<string, FileType> }, T>,
  equals?: EqualityChecker<T>
) {
  return useState<T>(useCallback((state) => selector({ ...state, data: fileData }), [selector]), equals);
}

function walkFiles(file: InnerFileType, callback?: (type: string, size: number) => void) {
  let filenames = [] as string[];
  file.files.forEach((nest) => {
    filenames.push(nest.path);
    walkFiles(nest, callback);
  });
  fileData.set(file.path, { ...file, files: filenames });
  callback?.(file.mime_type, file.size);
  return filenames;
}

export function setFileData(files: InnerFileType[]) {
  let mode = [] as FileProcessMode[];
  let totalSize = 0;
  files.forEach((file) => {
    walkFiles(file, (type, size) => {
      totalSize += size;
      if (mode.length === 3) return;
      if (type === 'dir' && !mode.includes('dir')) {
        return mode.push('dir');
      }
      if (type.startsWith('image') && !mode.includes('image')) {
        return mode.push('image');
      }
      if (type.startsWith('video') && !mode.includes('video')) {
        return mode.push('video');
      }
    })
  });
  useState.setState({ status: 'drop', mode, totalSize });
}

export function reset(data: Partial<FileStateType> = {}) {
  useState.setState({ ...defaultStatus, ...data });
  fileData.clear();
}
