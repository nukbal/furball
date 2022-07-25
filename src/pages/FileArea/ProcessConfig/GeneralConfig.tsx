import styled from 'styled-components';
import { Tab } from '@headlessui/react';
import { open } from '@tauri-apps/api/dialog';
import { useFormContext, Controller } from 'react-hook-form';

import Field, { HorizontalField } from '../../../components/Form/Field';
import Button from '../../../components/Button';
import Switch from '../../../components/Form/Switch';

import s from '../../../styles/static';

export default function GeneralConfig() {
  const { setValue, control } = useFormContext();

  const handleChangeDir = async () => {
    const res = await open({
      directory: true,
      multiple: false,
    });
    if (res) {
      setValue('path', Array.isArray(res) ? res[0] : res);
    }
  };

  return (
    <Tab.Panel data-tauri-drag-region>
      <Field>
        <h5>가능하면 덮어쓰기</h5>
        <Controller
          name="mode"
          control={control}
          render={({ field }) => (
            <Switch
              checked={field.value === 'overwrite'}
              onChange={() => field.onChange(field.value === 'path' ? 'overwrite' : 'path')}
            />
          )}
        />
        <small>작업한 파일이 같은이름의 같은확장자일시, 덮어씁니다.</small>
      </Field>
      <HorizontalField>
        <Field>
          <h5>저장 장소</h5>
          <HorizontalField style={{ marginTop: s.size['2'], marginBottom: s.size['2'] }}>
            <Controller
              name="path"
              control={control}
              render={({ field }) => <span>{field.value}</span>}
            />
            <DirBtn onClick={handleChangeDir}>
              폴더 바꾸기
            </DirBtn>
          </HorizontalField>
          <small>폴더처리등 새로운 파일이 생성되는 경우에도</small>
        </Field>
        <Field>
          <h5>처리후 파일 접미사</h5>
          <Controller
            name="suffix"
            control={control}
            render={({ field }) => (
              <input type="text" {...field} placeholder="예) _접미사" />
            )}
          />
          <small>{'[파일이름_접미사.ext] 같은 형태로 접미사를 지정합니다.'}</small>
        </Field>
      </HorizontalField>
    </Tab.Panel>
  );
}

const DirBtn = styled(Button)`
  background: ${({ theme }) => theme.gray300};
  padding-top: ${s.size['3']};
  padding-bottom: ${s.size['3']};
  margin-left: ${s.size['4']};
`;
