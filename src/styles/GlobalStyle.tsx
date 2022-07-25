import { createGlobalStyle } from 'styled-components';

export default createGlobalStyle`
  html { background-color: ${({ theme }) => theme.gray50}; color: ${({ theme }) => theme.gray800};}
  a { color: inherit; text-decoration:none; &:hover { text-decoration: underline; } }
`;
