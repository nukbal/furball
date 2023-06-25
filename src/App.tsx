import { onMount } from 'solid-js';

import { bootstrap } from 'models/config';

import Router from './pages';

export default function App() {
  onMount(() => {
    bootstrap();
  });
  return <Router />;
}
