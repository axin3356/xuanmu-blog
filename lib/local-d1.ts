import { existsSync, mkdirSync, readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'

type SqliteDatabase = {
  exec(sql: string): void
  prepare(sql: string): {
    all(...values: unknown[]): unknown[]
    get(...values: unknown[]): unknown
    run(...values: unknown[]): { lastInsertRowid?: number | bigint }
  }
}

type SqliteStatement = ReturnType<SqliteDatabase['prepare']>

let localDb: D1Database | undefined

export function getLocalD1Database(): D1Database {
  if (localDb) return localDb

  const dbPath = join(process.cwd(), '.local', 'xuanmu-blog.sqlite')
  const shouldInitialize = !existsSync(dbPath)
  mkdirSync(dirname(dbPath), { recursive: true })

  const db = openSqliteDatabase(dbPath)
  if (shouldInitialize) {
    db.exec(readFileSync(join(process.cwd(), 'db', 'schema.sql'), 'utf8'))
  }

  localDb = {
    prepare(query: string) {
      const statement = db.prepare(query)
      return new LocalD1PreparedStatement(statement)
    },
  }

  return localDb
}

function openSqliteDatabase(path: string): SqliteDatabase {
  const nodeRequire = eval('require') as NodeRequire
  const { DatabaseSync } = nodeRequire('node:sqlite') as {
    DatabaseSync: new (path: string) => SqliteDatabase
  }
  return new DatabaseSync(path)
}

class LocalD1PreparedStatement implements D1PreparedStatement {
  private values: unknown[] = []

  constructor(private readonly statement: SqliteStatement) {}

  bind(...values: unknown[]): D1PreparedStatement {
    this.values = values
    return this
  }

  async first<T = Record<string, unknown>>(): Promise<T | null> {
    return (this.statement.get(...this.values) as T | undefined) ?? null
  }

  async all<T = Record<string, unknown>>(): Promise<{ results: T[] }> {
    return { results: this.statement.all(...this.values) as T[] }
  }

  async run(): Promise<{ meta: { last_row_id: number } }> {
    const result = this.statement.run(...this.values)
    const lastRowId = Number(result.lastInsertRowid ?? 0)
    return { meta: { last_row_id: lastRowId } }
  }
}
