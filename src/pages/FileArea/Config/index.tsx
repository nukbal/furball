import { createSignal, Show, Switch, Match } from 'solid-js';
import type { SetStoreFunction } from 'solid-js/store';

import file from 'models/file';
import type { ConfigType } from 'models/config';
import Button from 'components/Button';

import GeneralConfig from './GeneralConfig';
import ImageConfig from './ImageConfig';
import DirConfig from './DirConfig';

type ConfigTabType = 'default' | 'image' | 'video' | 'dir';

interface Props {
  form: ConfigType;
  onChange: SetStoreFunction<ConfigType>;
}

export default function Config({ form, onChange }: Props) {
  const [tab, setTab] = createSignal<ConfigTabType>('default');

  const isImg = () => file().mode.includes('image') || file().mode.includes('dir');
  const isVideo = () => file().mode.includes('video');
  const isFolder = () => file().mode.includes('dir');

  return (
    <div class="bg-slate-900 py-2">
      <ol class="flex items-center space-x-1 px-2 pb-2">
        <Tab label="기본 설정" active={tab() === 'default'} onChange={() => setTab('default')} />
        <Show when={isImg()}>
          <Tab label="이미지" active={tab() === 'image'} onChange={() => setTab('image')} />
        </Show>
        <Show when={isVideo()}>
          <Tab label="비디오" active={tab() === 'video'} onChange={() => setTab('video')} />
        </Show>
        <Show when={isFolder()}>
          <Tab label="폴더" active={tab() === 'dir'} onChange={() => setTab('dir')} />
        </Show>
      </ol>
      <section class="p-4 pt-2 overflow-y-auto" style={{ 'max-height': '280px' }}>
        <Switch>
          <Match when={tab() === 'default'}>
            <GeneralConfig value={form} onChange={onChange} />
          </Match>
          <Match when={tab() === 'image'}>
            <ImageConfig value={form} onChange={onChange} />
          </Match>
          <Match when={tab() === 'dir'}>
            <DirConfig value={form} onChange={onChange} />
          </Match>
        </Switch>
      </section>
    </div>
  );
}

interface TabProps {
  active?: boolean;
  onChange: () => void;
  label: string;
}

function Tab(props: TabProps) {
  const className = () => {
    const defaultClass = 'flex flex-1 items-center justify-center h-7';
    return [defaultClass, props.active ? 'bg-sky-500' : ''].join(' ');
  };

  return (
    <Button class={className()} onClick={props.onChange}>
      {props.label}
    </Button>
  );
}
