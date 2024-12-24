// @ts-check

const eventz = new EventSource(`${window.location.pathname}/hot`)

eventz.addEventListener('head', (e) => {
  document.head.innerHTML = e.data
})
eventz.addEventListener('body', (e) => {
  document.body.innerHTML = e.data
})

// This is not 'ideal' but there is no way to close the connection from
// the server :(
eventz.onerror = (/** @type {Event} */ error) => {
  console.warn('Hot reload failed', error)
  eventz.close()
}
