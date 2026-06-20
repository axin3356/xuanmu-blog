import { mkdir, readFile, stat, writeFile } from 'node:fs/promises'
import { createReadStream } from 'node:fs'
import { dirname, join, relative, resolve } from 'node:path'
import { Readable } from 'node:stream'

type PutOptions = {
  httpMetadata?: {
    contentType?: string
    cacheControl?: string
  }
  customMetadata?: Record<string, string>
}

type Metadata = {
  httpMetadata?: {
    contentType?: string
    cacheControl?: string
  }
  customMetadata?: Record<string, string>
}

let localImageBucket: R2Bucket | undefined

export function getLocalImageBucket(): R2Bucket {
  if (localImageBucket) return localImageBucket

  const root = resolve(process.env.LOCAL_UPLOAD_DIR || join(process.cwd(), '.local', 'uploads'))

  localImageBucket = {
    async put(key: string, value: File | ArrayBuffer | ArrayBufferView | ReadableStream, options?: PutOptions) {
      const filePath = resolveObjectPath(root, key)
      await mkdir(dirname(filePath), { recursive: true })

      if (value instanceof File) {
        await writeFile(filePath, Buffer.from(await value.arrayBuffer()))
      } else if (value instanceof ReadableStream) {
        await writeFile(filePath, Buffer.from(await new Response(value).arrayBuffer()))
      } else {
        await writeFile(filePath, toBuffer(value as ArrayBuffer | ArrayBufferView))
      }

      await writeFile(
        metadataPath(filePath),
        JSON.stringify(
          {
            httpMetadata: options?.httpMetadata,
            customMetadata: options?.customMetadata,
          } satisfies Metadata,
          null,
          2,
        ),
        'utf8',
      )
    },

    async get(key: string, options?: { range?: { offset: number; length: number } }) {
      const filePath = resolveObjectPath(root, key)

      try {
        const info = await stat(filePath)
        const metadata = await readMetadata(filePath)
        const range = options?.range
        const stream = range
          ? createReadStream(filePath, {
              start: range.offset,
              end: range.offset + range.length - 1,
            })
          : createReadStream(filePath)

        return {
          body: Readable.toWeb(stream) as ReadableStream,
          httpEtag: `"${info.mtimeMs}-${info.size}"`,
          size: range?.length ?? info.size,
          customMetadata: metadata.customMetadata,
          writeHttpMetadata(headers: Headers) {
            if (metadata.httpMetadata?.contentType) {
              headers.set('content-type', metadata.httpMetadata.contentType)
            }
            if (metadata.httpMetadata?.cacheControl) {
              headers.set('cache-control', metadata.httpMetadata.cacheControl)
            }
          },
        } as R2ObjectBody & {
          size: number
          customMetadata?: Record<string, string>
        }
      } catch {
        return null
      }
    },

    async head(key: string) {
      const filePath = resolveObjectPath(root, key)

      try {
        const info = await stat(filePath)
        const metadata = await readMetadata(filePath)
        return {
          size: info.size,
          httpMetadata: metadata.httpMetadata,
        }
      } catch {
        return null
      }
    },
  } as R2Bucket

  return localImageBucket
}

function toBuffer(value: ArrayBuffer | ArrayBufferView) {
  if (value instanceof ArrayBuffer) {
    return Buffer.from(new Uint8Array(value))
  }

  return Buffer.from(value.buffer, value.byteOffset, value.byteLength)
}

function resolveObjectPath(root: string, key: string) {
  const filePath = resolve(root, key)
  const pathFromRoot = relative(root, filePath)
  if (pathFromRoot.startsWith('..') || pathFromRoot === '' || resolve(pathFromRoot) === pathFromRoot) {
    throw new Error('Invalid object key')
  }
  return filePath
}

function metadataPath(filePath: string) {
  return `${filePath}.meta.json`
}

async function readMetadata(filePath: string): Promise<Metadata> {
  try {
    return JSON.parse(await readFile(metadataPath(filePath), 'utf8')) as Metadata
  } catch {
    return {}
  }
}
