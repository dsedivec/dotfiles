// https://blog.echobind.com/integrating-prettier-eslint-airbnb-style-guide-in-vscode-47f07b5d7d6a
// https://github.com/paulolramos/eslint-prettier-airbnb-react/blob/master/eslint-prettier-config.sh

module.exports = {
  extends: ['airbnb', 'plugin:prettier/recommended', 'prettier'],
  plugins: ['import'],
  env: {
    browser: true
    // "commonjs": true,
    // "es6": true,
    // "jest": true,
    // "node": true
  },
  settings: {
    react: {
      version: "16.10",
    }
  },
  rules: {
    'max-len': [
      'warn',
      {
        code: 80,
        tabWidth: 2,
        comments: 80,
        ignoreComments: false,
        ignoreTrailingComments: true,
        ignoreUrls: true,
        ignoreStrings: true,
        ignoreTemplateLiterals: true,
        ignoreRegExpLiterals: true
      }
    ]
  }
};
