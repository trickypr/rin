// @ts-check

const eventz = new EventSource(`${window.location.pathname}/hot`)

eventz.addEventListener('head', (e) => {
  document.head.innerHTML = e.data
})
eventz.addEventListener('body', (e) => {
  document.body.innerHTML = e.data

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

// This is not 'ideal' but there is no way to close the connection from
// the server :(
eventz.onerror = (/** @type {Event} */ error) => {
  console.warn('Hot reload failed', error)
  eventz.close()
}
