// @ts-check
/// <reference lib="ESNext" />
/// <reference path="./editor.d.ts" />
/**
 * @fileoverview typescript lsp worker
 */

import { createDefaultMapFromCDN } from '@typescript/vfs'
import ts from 'typescript'
import * as Comlink from 'comlink'
import { createWorker } from '@valtown/codemirror-ts/worker'
import { createSystem } from '@typescript/vfs'
import { createVirtualTypeScriptEnvironment } from '@typescript/vfs'
import { setupTypeAcquisition } from '@typescript/ata'

const /** @type {import('typescript').CompilerOptions} */ COMPILER_OPTS = {
    target: ts.ScriptTarget.ES2024,
    allowJs: true,
    checkJs: true,
    lib: ['dom'],
    module: ts.ModuleKind.ES2022,
    moduleResolution: ts.ModuleResolutionKind.Bundler,
  }

let ata
/** @type {PromiseWithResolvers<void>} */
let ataDone

const exposed = {
  ...createWorker(async () => {
    const fsMap = await createDefaultMapFromCDN(
      COMPILER_OPTS,
      '5.7.2',
      false,
      ts,
    )
    const system = createSystem(fsMap)

    system.writeFile('/package.json', '{ "type": "module" }')

    ata = setupTypeAcquisition({
      projectName: 'Codepen Clone',
      typescript: ts,
      logger: console,
      delegate: {
        finished(vfs) {
          const env = exposed.getEnv()

          for (const [name, contents] of vfs) {
            if (env.getSourceFile(name)) {
              env.updateFile(name, contents)
            } else {
              env.createFile(name, contents)
            }
          }

          exposed
            .getEnv()
            .updateFile('script.js', system.readFile('script.js') || '')

          ataDone.resolve()
        },
      },
    })

    return createVirtualTypeScriptEnvironment(system, [], ts, COMPILER_OPTS)
  }),

  /** @param {{ file: string }} arg */
  async runAta({ file }) {
    ataDone = Promise.withResolvers()
    ata(file)
    await ataDone.promise
  },
}

Comlink.expose(exposed)

/**
 * @typedef {typeof exposed} LspWorker
 */
