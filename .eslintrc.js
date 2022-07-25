module.exports = {
  root: true,
  ignorePatterns: ['**/*.d.ts'],
  extends: [
    'react-app',
    'react-app/jest',
    'airbnb',
  ],
  plugins: ['@typescript-eslint'],
  parser: '@typescript-eslint/parser',
  settings: {
    'import/resolver': {
      node: {
        paths: ['src'],
        extensions: ['.ts', '.tsx', '.js'],
      },
    },
  },
  rules: {
    camelcase: 'off',
    'no-unused-vars': 'off',
    'import/extensions': 'off',
    'react/react-in-jsx-scope': 'off',
    'no-use-before-define': 'off',
    'import/no-unresolved': 'off',
    'function-paren-newline': 'off',
    'react/destructuring-assignment': 'off',
    'no-promise-executor-return': 'off',
    'react/require-default-props': 'off',
    'consistent-return': 'off',
    'react/jsx-filename-extension': [1, { extensions: ['.tsx'] }],
    'import/no-extraneous-dependencies': [1, {
      devDependencies: ['**/__test__/**', '**/*.test.{ts,tsx}', '**/setupTests.ts', '**/testUtils.tsx'],
    }],
  },
};
