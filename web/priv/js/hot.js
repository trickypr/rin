// @ts-check

import { socketEvents } from './socket.js'

// New deps in the import map require a reload to apply
socketEvents.on(
  'depChange',
  ({ change }) => change === 'add' && window.location.reload(),
)

socketEvents.on('swap', ({ target, content }) => {
  if (target === 'head') {
    document.head.innerHTML = content
    return
  }

  document.body.innerHTML = content

  // Trigger the inserted script
  const scripts = document.querySelectorAll('script[data-from="hot"]')
  for (const hotScript of scripts) {
    const newScript = document.createElement('script')
    ;[...hotScript.attributes].forEach(({ name, value }) =>
      newScript.setAttribute(name, value),
    )

    const scriptText = document.createTextNode(hotScript.innerHTML)
    newScript.appendChild(scriptText)

    hotScript.parentElement?.replaceChild(newScript, hotScript)
  }
})
