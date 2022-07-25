import { css } from 'styled-components';
import t from './static';

export const flex = {
  verticalCenter: css`display: flex; flex-direction: row; align-items: center;`,
  horizontalCenter: css`display: flex; flex-direction: row; justify-content: center;`,
  center: css`display: flex; justify-content: center; align-items: center;`,
  between: css`display: flex; justify-content: space-between; align-items: center;`,
};

export const text = {
  xs: css`font-size: ${t.size['3']}; line-height: ${t.size['4']};`,
  sm: css`font-size: ${t.size['3.5']}; line-height: ${t.size['5']};`,
  base: { lineHeight: t.size['6'], fontSize: t.size['4'] },
  lg: { lineHeight: t.size['10'], fontSize: t.size['8'] },
  xl: { lineHeight: t.size['7'], fontSize: t.size['5'] },
  '2xl': css`font-size: ${t.size['24']}; line-height: ${t.size['20']};`,
};

export const transition = {
  cubicBezier: 'cubic-bezier(0.25, 0.1, 0.25, 1)',
};

export const shadow = {
  sm: css`box-shadow: 0 1px 2px 0 rgb(0 0 0 / 0.05);`,
  base: css`box-shadow: 0 1px 3px 0 rgb(0 0 0 / 0.1), 0 1px 2px -1px rgb(0 0 0 / 0.1);`,
  md: css`box-shadow: 0 4px 6px -1px rgb(0 0 0 / 0.1), 0 2px 4px -2px rgb(0 0 0 / 0.1);`,
  lg: css`box-shadow: 0 10px 15px -3px rgb(0 0 0 / 0.1), 0 4px 6px -4px rgb(0 0 0 / 0.1);`,
  xl: css`box-shadow: 0 20px 25px -5px rgb(0 0 0 / 0.1), 0 8px 10px -6px rgb(0 0 0 / 0.1);`,
  inner: css`box-shadow: inset 0 2px 4px 0 rgb(0 0 0 / 0.05);`,
};

export const button = css`
  outline: none;
  background: transparent;
  border: none;
  border-radius: ${t.radius['lg']};
`;
