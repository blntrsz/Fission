import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { createRequire } from "node:module";
import {
  newThreadId,
  nowEpochSeconds,
  type AgentThread,
  type ThreadStatus
} from "./types";

type SqlJsDatabase = {
  run(sql: string, params?: unknown[]): void;
  exec(sql: string): void;
  prepare(sql: string): {
    bind(params: unknown[]): void;
    step(): boolean;
    getAsObject(): Record<string, unknown>;
    free(): void;
  };
  export(): Uint8Array;
};

type SqlJsModule = {
  Database: new (data?: Buffer | Uint8Array) => SqlJsDatabase;
};

const STATUSES = new Set<ThreadStatus>([
  "active",
  "settled",
  "completed",
  "failed",
  "cancelled"
]);

export class ThreadRepository {
  private constructor(
    private readonly db: SqlJsDatabase,
    private readonly path: string
  ) {}

  static async open(path: string): Promise<ThreadRepository> {
    const require = createRequire(import.meta.url);
    const initSqlJs = require("sql.js") as (config?: {
      locateFile?: (file: string) => string;
    }) => Promise<SqlJsModule>;
    const wasmDirectory = dirname(require.resolve("sql.js/dist/sql-wasm.wasm"));
    const SQL = await initSqlJs({
      locateFile: (file) => `${wasmDirectory}/${file}`
    });
    const db =
      path !== ":memory:" && existsSync(path)
        ? new SQL.Database(readFileSync(path))
        : new SQL.Database();
    const repository = new ThreadRepository(db, path);
    migrate(db);
    repository.persist();
    return repository;
  }

  create(thread: AgentThread): AgentThread {
    const existingCount = numberValue(
      this.selectOne("SELECT COUNT(*) AS count FROM threads", [])?.count,
      0
    );
    const sortIndex =
      existingCount === 0
        ? 0
        : numberValue(
            this.selectOne("SELECT MIN(sort_index) AS minimum FROM threads", [])?.minimum,
            0
          ) - 1;
    const stored = { ...thread, sortIndex };
    this.db.run(
      `INSERT INTO threads (
        id, title, status, working_directory, project_name, remote_machine_id,
        remote_command, created_at, updated_at, sort_index
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        stored.id,
        stored.title,
        stored.status,
        stored.workingDirectory,
        stored.projectName,
        stored.remoteMachineID,
        stored.remoteCommand,
        stored.createdAt,
        stored.updatedAt,
        stored.sortIndex
      ]
    );
    this.persist();
    return stored;
  }

  thread(id: string): AgentThread | null {
    const row = this.selectOne("SELECT * FROM threads WHERE id = ?", [id]);
    return row ? fromRow(row) : null;
  }

  list(): AgentThread[] {
    return this.selectAll(
      "SELECT * FROM threads ORDER BY sort_index ASC, updated_at DESC, id ASC",
      []
    ).map(fromRow);
  }

  update(thread: AgentThread): void {
    this.db.run(
      `UPDATE threads SET
        title = ?, status = ?, working_directory = ?, project_name = ?,
        remote_machine_id = ?, remote_command = ?, created_at = ?, updated_at = ?,
        sort_index = ?
      WHERE id = ?`,
      [
        thread.title,
        thread.status,
        thread.workingDirectory,
        thread.projectName,
        thread.remoteMachineID,
        thread.remoteCommand,
        thread.createdAt,
        thread.updatedAt,
        thread.sortIndex,
        thread.id
      ]
    );
    if (this.thread(thread.id) == null) {
      throw new Error("thread not found");
    }
    this.persist();
  }

  delete(id: string): void {
    if (this.thread(id) == null) {
      throw new Error("thread not found");
    }
    this.db.run("DELETE FROM threads WHERE id = ?", [id]);
    this.persist();
  }

  reorder(ids: string[]): void {
    ids.forEach((id, index) => {
      this.db.run("UPDATE threads SET sort_index = ? WHERE id = ?", [index, id]);
      if (this.thread(id) == null) {
        throw new Error("thread not found");
      }
    });
    this.persist();
  }

  close(): void {
    this.persist();
  }

  private selectOne(sql: string, params: unknown[]): Record<string, unknown> | null {
    return this.selectAll(sql, params)[0] ?? null;
  }

  private selectAll(sql: string, params: unknown[]): Record<string, unknown>[] {
    const statement = this.db.prepare(sql);
    statement.bind(params);
    const rows: Record<string, unknown>[] = [];
    while (statement.step()) {
      rows.push(statement.getAsObject());
    }
    statement.free();
    return rows;
  }

  private persist(): void {
    if (this.path === ":memory:") {
      return;
    }
    mkdirSync(dirname(this.path), { recursive: true });
    writeFileSync(this.path, Buffer.from(this.db.export()));
  }
}

export function createThreadInput(input: {
  id?: string;
  title: string;
  status?: ThreadStatus;
  workingDirectory?: string | null;
  projectName?: string | null;
  remoteMachineID?: string | null;
  remoteCommand?: string | null;
  createdAt?: number;
  updatedAt?: number;
  sortIndex?: number;
}): AgentThread {
  const createdAt = input.createdAt ?? nowEpochSeconds();
  return {
    id: input.id ?? newThreadId(),
    title: input.title,
    status: input.status ?? "active",
    workingDirectory: input.workingDirectory ?? null,
    projectName: input.projectName ?? null,
    remoteMachineID: input.remoteMachineID ?? null,
    remoteCommand: input.remoteCommand ?? null,
    createdAt,
    updatedAt: input.updatedAt ?? createdAt,
    sortIndex: input.sortIndex ?? 0
  };
}

function fromRow(row: Record<string, unknown>): AgentThread {
  const status = String(row.status) as ThreadStatus;
  if (!STATUSES.has(status)) {
    throw new Error("invalid stored thread");
  }
  return {
    id: String(row.id),
    title: String(row.title),
    status,
    workingDirectory: stringOrNull(row.working_directory),
    projectName: stringOrNull(row.project_name),
    remoteMachineID: stringOrNull(row.remote_machine_id),
    remoteCommand: stringOrNull(row.remote_command),
    createdAt: numberValue(row.created_at, 0),
    updatedAt: numberValue(row.updated_at, 0),
    sortIndex: numberValue(row.sort_index, 0)
  };
}

function stringOrNull(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

function numberValue(value: unknown, fallback: number): number {
  return typeof value === "number" ? value : fallback;
}

function migrate(db: SqlJsDatabase): void {
  if (pragmaUserVersion(db) < 1) {
    db.exec(`
      CREATE TABLE IF NOT EXISTS threads (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        status TEXT NOT NULL CHECK (status IN ('active', 'completed', 'failed', 'cancelled')),
        created_at DOUBLE NOT NULL,
        updated_at DOUBLE NOT NULL
      );
      CREATE INDEX IF NOT EXISTS threads_updated_at ON threads(updated_at);
      PRAGMA user_version = 1;
    `);
  }
  if (pragmaUserVersion(db) < 2) {
    ensureColumn(db, "working_directory", "TEXT");
    db.exec("PRAGMA user_version = 2");
  }
  if (pragmaUserVersion(db) < 3) {
    db.exec(`
      CREATE TABLE threads_with_settled_status (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        status TEXT NOT NULL CHECK (status IN ('active', 'settled', 'completed', 'failed', 'cancelled')),
        working_directory TEXT,
        created_at DOUBLE NOT NULL,
        updated_at DOUBLE NOT NULL
      );
      INSERT INTO threads_with_settled_status
        (id, title, status, working_directory, created_at, updated_at)
      SELECT id, title, status, working_directory, created_at, updated_at
      FROM threads;
      DROP TABLE threads;
      ALTER TABLE threads_with_settled_status RENAME TO threads;
      CREATE INDEX threads_updated_at ON threads(updated_at);
      PRAGMA user_version = 3;
    `);
  }
  if (pragmaUserVersion(db) < 4) {
    ensureColumn(db, "project_name", "TEXT");
    db.exec("PRAGMA user_version = 4");
  }
  if (pragmaUserVersion(db) < 5) {
    ensureColumn(db, "sort_index", "INTEGER NOT NULL DEFAULT 0");
    db.exec(`
      UPDATE threads SET sort_index = (
        SELECT COUNT(*) FROM threads AS other
        WHERE other.updated_at > threads.updated_at
           OR (
                other.updated_at = threads.updated_at
                AND other.id < threads.id
           )
      );
      PRAGMA user_version = 5;
    `);
  }
  if (pragmaUserVersion(db) < 6) {
    ensureColumn(db, "remote_machine_id", "TEXT");
    ensureColumn(db, "remote_command", "TEXT");
    db.exec("PRAGMA user_version = 6");
  }
}

function pragmaUserVersion(db: SqlJsDatabase): number {
  const statement = db.prepare("PRAGMA user_version");
  statement.step();
  const row = statement.getAsObject();
  statement.free();
  return numberValue(Object.values(row)[0], 0);
}

function ensureColumn(db: SqlJsDatabase, name: string, definition: string): void {
  const statement = db.prepare("PRAGMA table_info(threads)");
  const names: string[] = [];
  while (statement.step()) {
    const row = statement.getAsObject();
    names.push(String(row.name));
  }
  statement.free();
  if (names.includes(name)) {
    return;
  }
  db.exec(`ALTER TABLE threads ADD COLUMN ${name} ${definition}`);
}
