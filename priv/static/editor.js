// @ts-check

import { defaultKeymap } from 'https://cdn.jsdelivr.net/npm/@codemirror/commands@6.7.1/+esm'
import { EditorState } from 'https://cdn.jsdelivr.net/npm/@codemirror/state@6.5.0/+esm'
import {
  EditorView,
  keymap,
} from 'https://cdn.jsdelivr.net/npm/@codemirror/view@6.36.1/+esm'

/** @type {HTMLDivElement[]} */
const editors = [...document.querySelectorAll('.editor')]
console.log(editors)

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

for (const editor of editors) {
  const doc = editor.innerText
  let lastSave = doc
  editor.innerHTML = ''

  const state = EditorState.create({
    doc,
    extensions: [
      keymap.of(defaultKeymap),
      EditorView.updateListener.of(
        debounce(1000, (updates) => {
          const lastUpdate = updates.pop()
          if (!lastUpdate) return
          const body = lastUpdate.state.doc.toString()
          if (body === lastSave) return
          lastSave = body

          fetch(`${window.location.href}/${editor.dataset.type}`, {
            method: 'PUT',
            body,
          })
        }),
      ),
    ],
  })

  new EditorView({ state, parent: editor })
}
