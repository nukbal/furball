import { createSignal, Show, Switch, Match } from 'solid-js';
import { createStore } from 'solid-js/store';

import file from 'models/file';
import config, { setConfig } from 'models/config';
import ChevronLeft from 'components/Icons/ChevronLeft';
import Button from 'components/Button';
import { setPageMode } from 'models/mode';

import GeneralConfig from './GeneralConfig';
import ImageConfig from './ImageConfig';
import DirConfig from './DirConfig';

type ConfigTypes = 'default' | 'image' | 'video' | 'dir';

export default function Config() {
  const [tab, setTab] = createSignal<ConfigTypes>('default');
  const [form, setForm] = createStore({ ...config });

  const isImg = () => file().mode.includes('image');
  const isVideo = () => file().mode.includes('video');
  const isFolder = () => file().mode.includes('dir');

  const handleClose = () => setPageMode('cancel');

  const handleSubmit = () => {
    setConfig({ ...form });
    handleClose();
  };

  return (
    <div class="flex flex-col h-full" data-tauri-drag-region>
      <header class="px-2 pt-2 mb-1" data-tauri-drag-region>
        <Button onClick={() => setPageMode('cancel')}>
          <ChevronLeft class="w-6 h-6" />
        </Button>
      </header>
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
      <section class="flex-auto p-4 pt-2 overflow-y-auto" style={{ 'max-height': 'calc(100vh - 155px)' }}>
        <Switch>
          <Match when={tab() === 'default'}>
            <GeneralConfig value={form} onChange={setForm} />
          </Match>
          <Match when={tab() === 'image'}>
            <ImageConfig value={form} onChange={setForm} />
          </Match>
          <Match when={tab() === 'dir'}>
            <DirConfig value={form} onChange={setForm} />
          </Match>
        </Switch>
      </section>
      <footer class="flex-none text-right pt-2 px-4 space-x-1" data-tauri-drag-region>
        <Button class="w-24 h-9" onClick={handleClose}>
          취소하기
        </Button>
        <Button class="w-24 h-9" onClick={handleSubmit}>
          적용하기
        </Button>
      </footer>
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
    const defaultClass = 'flex flex-1 items-center justify-center h-9';
    return [defaultClass, props.active ? 'bg-sky-500' : ''].join(' ');
  };

  return (
    <Button class={className()} onClick={props.onChange}>
      {props.label}
    </Button>
  );
}
