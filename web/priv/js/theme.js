import { createTheme } from 'thememirror'
import { tags as t } from '@lezer/highlight'

export const codemirror = createTheme({
  variant: 'light',
  settings: {
    background: '#fff',
    foreground: '#1c1814',
    caret: '#a15ccd',
    selection: '#efdaff',
    lineHighlight: '#8a91991a',
    gutterBackground: '#fff',
    gutterForeground: '#cabdb3',
  },
  styles: [
    {
      tag: t.comment,
      color: '#b6ada6',
    },
    {
      tag: t.variableName,
      color: '#3c342e',
    },
    {
      tag: [t.string, t.special(t.brace)],
      color: '#40a02b',
    },
    {
      tag: t.number,
      color: '#fe640b',
    },
    {
      tag: t.bool,
      color: '#fe640b',
    },
    {
      tag: t.null,
      color: '#fe640b',
    },
    {
      tag: t.keyword,
      color: '#8839ef',
    },
    {
      tag: t.operator,
      color: '#04a5e5',
    },
    {
      tag: t.className,
      color: '#df8e1d',
    },
    {
      tag: t.definition(t.typeName),
      color: '#df8e1d',
    },
    {
      tag: t.typeName,
      color: '#df8e1d',
    },
    {
      tag: t.angleBracket,
      color: '#1e66f5',
    },
    {
      tag: t.tagName,
      color: '#1e66f5',
    },
    {
      tag: t.attributeName,
      color: '#df8e1d',
    },
  ],
})
