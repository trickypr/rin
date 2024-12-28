// @ts-check

const socket = new WebSocket(
  `ws${window.location.protocol === 'https' ? 's' : ''}://${window.location.host}${window.location.pathname}/live`,
)

socket.addEventListener('message', ({ data }) => {
  const /** @type {string[]} */ split = data.split(' ')

  switch (split.shift()) {
    case 'swap':
      swap(split.shift(), split.join(' '))
      break
  }
})

/**
 * @param {'head' | 'body'} target
 * @param {string} content
 */
function swap(target, content) {
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
}
