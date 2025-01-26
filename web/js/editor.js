// @ts-check
/// <reference path="./editor.d.ts" />

import { defaultKeymap, indentWithTab } from '@codemirror/commands'
import { EditorState, StateEffect, Prec } from '@codemirror/state'
import { EditorView, keymap } from '@codemirror/view'
import { basicSetup } from 'codemirror'
import { syntaxTree } from '@codemirror/language'
import { autocompletion } from '@codemirror/autocomplete'
import { characterEntities } from 'character-entities'
import { continueKeymap } from '@valtown/codemirror-continue'

import { codemirror } from './editor/theme.js'
import { socketEvents } from './socket.js'

/** @type {HTMLDivElement[]} */
const editors = [...document.querySelectorAll('.editor')]

export let /** @type {Record<'head' | 'body' | 'css' | 'js', EditorView | null>} */ editorMap =
    {
      head: null,
      body: null,
      css: null,
      js: null,
    }

/**
 * @param {EditorView} editor
 * @param {string} key
 * @param {Set<string>} set
 */
function fetchAttributes(editor, key, set) {
  const regex = new RegExp(`${key}="(?<value>.*?)"`, 'gm')
  const code = editor.state.doc.toString()

  let match = regex.exec(code)

  while (match !== null) {
    const value = match.groups.value
    value.split(' ').forEach((v) => set.add(v))
    match = regex.exec(code)
  }
}

const typescriptWorker = import('comlink').then(async (Comlink) => {
  const innerWorker = new Worker(new URL('./editor__lsp.js', import.meta.url), {
    type: 'module',
  })
  const /** @type {import('comlink').Remote<import('./editor__lsp.js').LspWorker>} */ worker =
      Comlink.wrap(innerWorker)
  await worker.initialize()
  return worker
})

const langMap = {
  head: async (loc = 'head') =>
    [
      ...(await import('@codemirror/lang-html').then((p) => [
        p.html(),

        p.htmlLanguage.data.of({
          autocomplete: (
            /** @type {import('@codemirror/autocomplete').CompletionContext} */ context,
          ) => {
            const { state, pos } = context
            const tree = syntaxTree(state)
            const node = tree.resolveInner(pos, -1)
            const nodePrev = node.prevSibling

            if (!nodePrev || nodePrev.name !== 'InvalidEntity') return

            return {
              from: node.from,
              options: Object.entries(characterEntities).map(
                ([label, detail]) => ({
                  label: label + ';',
                  detail,
                  type: 'text',
                }),
              ),
            }
          },
        }),
      ])),
      // await import('@overleaf/codemirror-tree-view').then((p) => p.treeView),
      ...(await import('@emmetio/codemirror6-plugin').then((p) => [
        p.abbreviationTracker(),
        keymap.of([
          {
            key: 'c-e',
            run: p.expandAbbreviation,
          },
          {
            key: 'c-s-e',
            run: p.enterAbbreviationMode,
          },
        ]),
      ])),

      loc == 'body' &&
        EditorView.updateListener.of(
          debounce(50, async (update) => {
            const ids = new Set()
            const classes = new Set()

            fetchAttributes(update[0].view, 'id', ids)
            fetchAttributes(update[0].view, 'class', classes)

            const idTypes = [...ids].map(
              (
                id,
              ) => `getElementById<E extends HTMLElement = HTMLElement>(elementId: '${id}'): E;
                    querySelector<E extends HTMLElement = HTMLElement>(query: '#${id}'): E;`,
            )
            const classTypes = [...classes].map(
              (
                c,
              ) => `getElementsByClassName<E extends HTMLElement = HTMLElement>(className: '${c}'): HTMLCollection;
                    querySelector<E extends HTMLElement = HTMLElement>(query: '.${c}'): E;
                    querySelectorAll<E extends HTMLElement = HTMLElement>(query: '.${c}'): NodeList;`,
            )

            const typeFile = `export {}; declare global { interface Document { ${idTypes.join(' ')} ${classTypes.join(' ')} } }`
            const worker = await typescriptWorker
            worker.updateFile({ path: 'index.d.ts', code: typeFile })
          }),
        ),
    ].filter(Boolean),
  body: () => langMap['head']('body'),
  css: async () => [
    ...(await import('@codemirror/lang-css').then((p) => [
      p.css(),
      p.cssLanguage.data.of({
        autocomplete: (
          /** @type {import('@codemirror/autocomplete').CompletionContext} */ context,
        ) => {
          const { state, pos } = context
          const node = syntaxTree(state).resolveInner(pos, -1)

          if (node.name == 'IdName' || node.name == '#') {
            const ids = new Set()
            if (editorMap.body) fetchAttributes(editorMap.body, 'id', ids)
            if (editorMap.head) fetchAttributes(editorMap.head, 'id', ids)

            return {
              from: node.from,
              options: [...ids].map((label) => ({
                label,
                type: 'namespace',
              })),
            }
          }

          if (node.name == 'ClassName') {
            const classes = new Set()
            if (editorMap.body)
              fetchAttributes(editorMap.body, 'class', classes)
            if (editorMap.head)
              fetchAttributes(editorMap.head, 'class', classes)

            return {
              from: node.from,
              options: [...classes].map((label) => ({
                label,
                type: 'namespace',
              })),
            }
          }
        },
      }),
    ])),
    // await import('@overleaf/codemirror-tree-view').then((p) => p.treeView),
  ],
  js: async () => [
    await import('@codemirror/lang-javascript').then((p) => p.javascript()),
    ...(await Promise.all([
      import('@valtown/codemirror-ts'),
      typescriptWorker,
    ]).then(([valtown, worker]) => [
      valtown.tsFacetWorker.of({ worker, path: 'script.js' }),
      valtown.tsSyncWorker(),
    ])),
    Prec.high(keymap.of(continueKeymap)),
  ],
}

/**
 * @template P
 * @param {number} delay
 * @param {(updates: P[]) => void} fn
 * @returns {(v: P) => void}
 */
function debounce(delay, fn, maxBuffer = 10) {
  let timeout = null
  let params = []
  return (update) => {
    params.push(update)
    if (timeout) clearTimeout(timeout)

    if (params.length > maxBuffer) {
      fn(params)
      params = []
      return
    }

    timeout = setTimeout(() => {
      fn(params)
      params = []
    }, delay)
  }
}

window.addEventListener('load', (_) => {
  editors.forEach(async (editor) => {
    const doc = editor.innerText
    const /** @type {{ type: 'head' | 'body' | 'css' | 'js' }} */ { type } =
        editor.dataset
    let lastSave = doc
    editor.innerHTML = ''

    // JS is a lot more costly to evaluate and doesn't really have a stable
    // intermeidate state, so we make these a lot larger
    const timeout = type === 'js' ? 1000 : 200
    const buffer = type === 'js' ? 1000 : 4

    const state = EditorState.create({
      doc,
      extensions: [
        basicSetup,
        codemirror,
        keymap.of(defaultKeymap),
        EditorView.lineWrapping,
        EditorView.updateListener.of(
          debounce(
            timeout,
            (updates) => {
              const lastUpdate = updates.pop()
              if (!lastUpdate) return
              const body = lastUpdate.state.doc.toString()
              if (body === lastSave) return
              lastSave = body

              fetch(`${window.location.href}/${editor.dataset.type}`, {
                method: 'PUT',
                body,
              })
            },
            buffer,
          ),
        ),
      ],
    })

    editorMap[type] = new EditorView({
      state,
      parent: editor,
    })

    queueMicrotask(async () => {
      const langExtensions = await langMap[type]()
      editorMap[type]?.dispatch({
        effects: StateEffect.appendConfig.of([
          ...langExtensions,
          keymap.of([indentWithTab]),
        ]),
      })

      if (type === 'js') {
        const worker = await typescriptWorker
        await worker.runAta({ file: doc })
        const valtown = await import('@valtown/codemirror-ts')
        editorMap[type]?.dispatch({
          effects: StateEffect.appendConfig.of([
            valtown.tsLinterWorker(),
            autocompletion({ override: [valtown.tsAutocompleteWorker()] }),
            valtown.tsHoverWorker(),
          ]),
        })
      }
    })
  })
})

socketEvents.on('depChange', async ({ change, packageName }) => {
  console.info('depChange', change, packageName)

  if (change === 'remove') {
    // For the moment, we don't care
    return
  }

  // Force an ata reevaluation
  const worker = await typescriptWorker
  await worker.runAta({ file: editorMap.js.state.doc.toString() })
  // TODO: Force linter to re run
})
