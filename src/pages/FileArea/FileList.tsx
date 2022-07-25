import { useMemo, useCallback } from 'react';
import styled from 'styled-components';

import FolderIcon from '../../components/Icons/Folder';
import FilmIcon from '../../components/Icons/Film';
import PhotoIcon from '../../components/Icons/Photo';

import { useFile } from '../../models/file';
import s from '../../styles/static';
import nonNullable from '../../utils/nonNullable';
import parseFileSize from '../../utils/parseFileSize';

interface ItemProps {
  path: string;
  nest?: number;
}

function FileItem({ path, nest = 0 }: ItemProps) {
  const data = useFile(useCallback(({ data }) => data.get(path) ?? null, [path]));

  const [paddingLeft, maxWidth] = useMemo(() => {
    if (nest === 1) return [s.size['8'], '245px'];
    if (nest === 2) return [s.size['16'], '225px'];
    return [s.size['2'], '265px'];
  }, [nest]);

  if (!data) return null;
  return (
    <>
      <ListItem style={{ paddingLeft }}>
        <div>
          {getMimeIcon(data.mime_type)}
          <abbr title={data.path} style={{ maxWidth }}>{data.filename}</abbr>
        </div>
        <small>{data.is_dir ? data.files.length : parseFileSize(data.size)}</small>
      </ListItem>
      {data.files?.map((item) => (
        <FileItem key={item} path={item} nest={nest + 1} />
      ))}
    </>
  );
}

export default function FileList() {
  const files = useFile(useCallback(({ data, paths }) => paths.map((path) => data.get(path)).filter(nonNullable), []));
  const totalSize = useFile(useCallback(({ totalSize }) => totalSize, []));
  const len = useFile(useCallback(({ data }) => data.size, []));

  return (
    <>
      <List>
        {files.map((file) => (
          <FileItem key={file.path} path={file.path} />
        ))}
      </List>
      <FileStatus>
        <small>총 {len}개</small>
        <small>{parseFileSize(totalSize)}</small>
      </FileStatus>
    </>
  );
}

function getMimeIcon(mimeType: string) {
  if (mimeType === 'dir') return <FolderIcon />;
  if (mimeType.startsWith('video')) return <FilmIcon />;
  return <PhotoIcon />;
}

const List = styled.ul`
  list-style-type: none;
  margin: 0;
  padding: 0;
  flex: auto;
  overflow-y: auto;
  min-height: 165px;
  max-height: 165px;
  margin-top: ${s.size['2']};
  user-select: none;
`;

const ListItem = styled.li`
  display: flex;
  align-items: center;
  justify-content: space-between;
  flex-wrap: wrap;
  height: ${s.size['10']};
  font-size: ${s.size['6']};
  padding: 0 ${s.size['2']};

  & > div {
    display: flex;
    align-items: center;
  }

  abbr {
    overflow: hidden;
    text-overflow: ellipsis;
    margin-right: ${s.size['4']};
    text-decoration: none;
    white-space: nowrap;
  }

  svg {
    width: ${s.size['6']};
    height: ${s.size['6']};
    margin-right: ${s.size['2']};
  }

  &:nth-child(2n - 1) {
    background: ${({ theme }) => theme.gray100};
  }

  &:nth-child(2n) {
    background: ${({ theme }) => theme.gray300};
  }
`;

const FileStatus = styled.footer`
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin: ${s.size['2']} 0;
`;
