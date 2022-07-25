import { useCallback } from 'react';
import styled from 'styled-components';

import FileIcon from '../../components/Icons/File';

import { useFile } from '../../models/file';
import s from '../../styles/static';

export default function Preview() {
  const thumbnail = useFile(useCallback(({ data, paths }) => {
    const parent = data.get(paths[0]);
    if (parent?.thumbnail) return parent?.thumbnail;
    if (parent?.is_dir) {
      const child = data.get(parent?.files[0]);
      return child?.thumbnail;
    }
    return undefined;
  }, []));

  return (
    <PreviewArea>
      {thumbnail ? (
        <img src={`data:image/jpeg;base64,${thumbnail}`} />
      ) : <FileIcon />}
    </PreviewArea>
  );
}

const PreviewArea = styled.figure`
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;

  width: 100%;
  max-width: ${s.size['64']};
  height: ${s.size['96']};
  margin: 0;
  margin-left: ${s.size['1.5']};
  margin-right: ${s.size['5']};
  pointer-events: none;

  img {
    max-width: 100%;
    max-height: 100%;
    object-fit: contain;
    border-radius: ${s.radius['lg']};
  }

  div {
    width: ${s.size['64']};
    height: ${s.size['96']};
    border-radius: ${s.radius['lg']};
    background-position: center;
    background-size: contain;
    background-repeat: no-repeat;
  }

  svg {
    width: ${s.size['24']};
    height: ${s.size['24']};
  }
`;
