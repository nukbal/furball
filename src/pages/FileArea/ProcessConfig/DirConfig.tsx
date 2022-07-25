import { Tab } from '@headlessui/react';
import styled from 'styled-components';
import { useFormContext, Controller } from 'react-hook-form';

import Field from '../../../components/Form/Field';
import Radio from '../../../components/Form/Radio';

import s from '../../../styles/static';

export default function DirConfig() {
  const { control, watch } = useFormContext();

  return (
    <Tab.Panel>
      <Field>
        폴더 처리 방식
        <Controller
          name="dir_mode"
          control={control}
          render={({ field: { name, onChange, value } }) => (
            <>
              <RadioButton name={name} value="none" onChange={onChange} checked={value === 'none'}>
                <span>개별처리</span>
                <small>폴더 내부의 파일을 개별처리합니다.</small>
              </RadioButton>
              <RadioButton name={name} value="pdf" onChange={onChange} checked={value === 'pdf'}>
                <span>PDF생성</span>
                <small>해당 폴더가 이미지만 포함할 경우, pdf로 생성합니다.</small>
              </RadioButton>
              <RadioButton name={name} value="zip" onChange={onChange} checked={value === 'zip'}>
                <span>압축하기</span>
                <small>해당 폴더의 미디어파일을 zip파일로 압축합니다.</small>
              </RadioButton>
            </>
          )}
        />
      </Field>
    </Tab.Panel>
  );
}

const RadioButton = styled(Radio)`
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  padding: ${s.size['4']};
  width: 100%;
  max-width: 25rem;
  
  small {
    margin-top: ${s.size['2']};
  }
`;
