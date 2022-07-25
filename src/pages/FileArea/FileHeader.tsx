import { useCallback } from 'react';
import styled from 'styled-components';
import { useFile } from '../../models/file';

export default function FileHeader() {
  const filename = useFile(useCallback(({ data, paths }) => data.get(paths[0])?.filename ?? '', []));
  const counts = useFile(useCallback(({ paths, data }) => data.size, []));

  return (
    <FileTitle data-tauri-drag-region>
      <span>{filename}</span>
      {counts > 1 ? ` (+${counts - 1})` : null}
    </FileTitle>
  );
}

const FileTitle = styled.header`
  display: flex;
  align-items: center;
  pointer-events: none;

  span {
    display: block;
    max-width: 425px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
`;
