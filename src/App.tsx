import { ThemeProvider } from 'styled-components';

import Router from './pages';
import useDarkMode from './hooks/useDarkMode';
import GlobalStyle from './styles/GlobalStyle';

import darkTheme from './styles/theme/dark';
import lightTheme from './styles/theme/light';

export default function App() {
  const { isDarkMode } = useDarkMode();
  return (
    <ThemeProvider theme={isDarkMode ? darkTheme : lightTheme}>
      <GlobalStyle />
      <Router />
    </ThemeProvider>
  );
}
