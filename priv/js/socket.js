// @ts-check

import mitt from 'mitt'

/**
 * @typedef {object} Events
 * @property {{ target: 'head' | 'body', content: string }} swap
 * @property {{ change: 'add' | 'remove', packageName: string }} depChange
 */

/** @type {import('mitt').Emitter<Events>} */
export const socketEvents = mitt()

const socket = new WebSocket(
  `ws${window.location.protocol === 'https' ? 's' : ''}://${window.location.host}${window.location.pathname}/live`,
)

socket.addEventListener('message', ({ data }) => {
  const /** @type {string[]} */ split = data.split(' ')

  switch (split.shift()) {
    case 'swap':
      socketEvents.emit('swap', {
        target: split.shift(),
        content: split.join(' '),
      })
      break

    case 'dep':
      socketEvents.emit('depChange', {
        change: split.shift(),
        packageName: split.join(' '),
      })
      break
  }
})
