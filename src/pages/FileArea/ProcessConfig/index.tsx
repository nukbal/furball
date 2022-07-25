import { useCallback } from 'react';
import styled from 'styled-components';
import { Tab } from '@headlessui/react';
import { transparentize } from 'polished';
import { FormProvider } from 'react-hook-form';

import s from '../../../styles/static';
import { shadow, transition } from '../../../styles/mixins';
import { useFile } from '../../../models/file';
import Button from '../../../components/Button';
import * as config from '../../../models/config';

import GeneralConfig from './GeneralConfig';
import ImageConfig from './ImageConfig';
import DirConfig from './DirConfig';
import useConfigForm from './useConfigForm';

interface Props {
  onClose: () => void;
}

export default function Config({ onClose }: Props) {
  const mode = useFile(useCallback(({ mode }) => ({
    img: mode.includes('image'),
    vid: mode.includes('video'),
    dir: mode.includes('dir'),
  }), []));

  const methods = useConfigForm();

  const handleSave = methods.handleSubmit(async (value) => {
    await config.setConfig(value);
    onClose();
  });

  return (
    <FormProvider {...methods}>
      <Tab.Group>
        <TabList>
          <Tab className={({ selected }) => selected ? 'active' : ''}>기본 설정</Tab>
          {mode.img && <Tab className={({ selected }) => selected ? 'active' : ''}>이미지</Tab>}
          {mode.vid && <Tab className={({ selected }) => selected ? 'active' : ''}>비디오</Tab>}
          {mode.dir && <Tab className={({ selected }) => selected ? 'active' : ''}>폴더</Tab>}
        </TabList>
        <PanelGroup>
          <GeneralConfig />
          {mode.img && <ImageConfig />}
          {mode.vid && <Tab.Panel>VIDEO</Tab.Panel>}
          {mode.dir && <DirConfig />}
        </PanelGroup>
      </Tab.Group>
      <ConfigFooter data-tauri-drag-region>
        <Button onClick={onClose}>
          취소하기
        </Button>
        <Button onClick={handleSave}>
          적용하기
        </Button>
      </ConfigFooter>
    </FormProvider>
  );
}

const TabList = styled(Tab.List)`
  display: flex;
  background: ${({ theme }) => transparentize(0.95, theme.blue400)};
  padding: ${s.size['2']};
  border-radius: ${s.radius['lg']};

  button {
    flex: 1;
    border-radius: ${s.radius['lg']};
    padding: ${s.size['3']};
    color: ${({ theme }) => theme.gray800};
    outline: none;
    border: none;
    background: transparent;
    transition: box-shadow 200ms ${transition.cubicBezier};
    cursor: pointer;

    &:hover {
      background: ${({ theme }) => transparentize(0.85, theme.gray50)};
    }

    &:focus, &:active {
      ${shadow.md}
    }

    &.active {
      background: ${({ theme }) => theme.gray50};
      cursor: default;
    }
  }

  & > * + * {
    margin-left: ${s.size['2']};
  }
`;

const PanelGroup = styled(Tab.Panels)`
  margin-top: ${s.size['2']};
  max-height: calc(100vh - 12.5rem);
  overflow-y: auto;
  user-select: none;
`;

const ConfigFooter = styled.footer`
  position: absolute;
  left: 0;
  right: 0;
  bottom: ${s.size['2']};
  display: flex;
  justify-content: flex-end;
  padding: ${s.size['2']} ${s.size['5']};

  & > * + * {
    margin-left: ${s.size['2']};
  }

  & > button {
    &:first-child {
      background: ${({ theme }) => theme.red500};

      &:hover {
        background: ${({ theme }) => theme.red400};
      }
    }
    &:last-child {
      background: ${({ theme }) => theme.green500};

      &:hover {
        background: ${({ theme }) => theme.green400};
      }
    }
  }
`;
