// @ts-check
/// <reference path="./editor.d.ts" />

import { defaultKeymap } from '@codemirror/commands'
import { EditorState } from '@codemirror/state'
import { EditorView, keymap } from '@codemirror/view'
import { basicSetup } from 'codemirror'
import { codemirror } from './theme.js'

/** @type {HTMLDivElement[]} */
const editors = [...document.querySelectorAll('.editor')]

const langMap = {
  head: () => import('@codemirror/lang-html').then((p) => p.html),
  body: () => langMap['head'](),
  css: () => import('@codemirror/lang-css').then((p) => p.css),
  js: () => import('@codemirror/lang-javascript').then((p) => p.javascript),
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

editors.forEach(async (editor) => {
  const doc = editor.innerText
  const { type } = editor.dataset
  let lastSave = doc
  editor.innerHTML = ''

  const langExtension = await langMap[type]()
  const state = EditorState.create({
    doc,
    extensions: [
      basicSetup,
      codemirror,
      langExtension(),
      keymap.of(defaultKeymap),
      EditorView.updateListener.of(
        debounce(
          200,
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
          4,
        ),
      ),
    ],
  })

  new EditorView({
    state,
    parent: editor,
  })
})
