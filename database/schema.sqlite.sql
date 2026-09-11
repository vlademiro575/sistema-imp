-- =====================================================================
-- SISTEMA IMP - SCHEMA DE BANCO DE DADOS (SQLite)
-- Stack: PHP 8 + CodeIgniter 4 + Linux OS Spooler (CUPS/Shell)
-- =====================================================================

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------
-- 1. TABELA: users (Usuários e Autenticação)
-- Controla o acesso restrito e os perfis da plataforma.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'user' CHECK(role IN ('admin', 'manager', 'user')),
    status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active', 'inactive', 'suspended')),
    created_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime'))
);

-- ---------------------------------------------------------------------
-- 2. TABELA: printers (Impressoras / Filas do Sistema Operacional)
-- Mapeia filas gerenciadas pelo Linux (ex: CUPS, lp, lpr).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS printers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,                  -- Nome de exibição amigável
    system_queue_name TEXT NOT NULL UNIQUE,      -- Nome exato da fila no SO (ex: 'PRINTER_RH_P2')
    location TEXT,                              -- Localização física (ex: 'Andar 2 - Sala 204')
    description TEXT,
    is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1)),
    created_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime'))
);

-- ---------------------------------------------------------------------
-- 3. TABELA: user_quotas (Cotas Mensais de Páginas)
-- Controla a cota atribuída e consumida por usuário em cada período mensal.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_quotas (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    period_year_month TEXT NOT NULL,            -- Formato 'AAAA-MM' (ex: '2026-09')
    allocated_pages INTEGER NOT NULL DEFAULT 0 CHECK(allocated_pages >= 0),
    used_pages INTEGER NOT NULL DEFAULT 0 CHECK(used_pages >= 0),
    created_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
    
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    UNIQUE (user_id, period_year_month),
    CHECK (used_pages <= allocated_pages)       -- Garante integridade: não gasta além da cota
);

-- ---------------------------------------------------------------------
-- 4. TABELA: print_jobs (Trabalhos de Impressão e Análise de PDFs)
-- Registra uploads de PDFs, contagem via pdfinfo e status de envio.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS print_jobs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    printer_id INTEGER NOT NULL,
    original_filename TEXT NOT NULL,            -- Nome do arquivo original
    stored_filename TEXT NOT NULL UNIQUE,       -- Nome salvo no disco seguro (UUID/Hash)
    file_path TEXT NOT NULL,                    -- Caminho absoluto no servidor
    file_size_bytes INTEGER NOT NULL CHECK(file_size_bytes > 0),
    file_hash_sha256 TEXT NOT NULL,             -- Checksum para integridade e auditoria
    page_count INTEGER NOT NULL DEFAULT 0 CHECK(page_count >= 0),
    status TEXT NOT NULL DEFAULT 'pending' CHECK(
        status IN (
            'pending',                          -- Arquivo recebido
            'analyzing',                        -- Inspecionando páginas com pdfinfo
            'approved',                         -- Páginas validadas e cota aprovada
            'rejected_quota',                   -- Cota insuficiente
            'rejected_invalid_pdf',             -- Arquivo corrompido ou formato ilegível
            'printing',                         -- Em execução no script externo do SO
            'completed',                        -- Impresso com sucesso
            'failed',                           -- Falha no comando/script externo
            'cancelled'                         -- Cancelado pelo usuário ou admin
        )
    ),
    system_command TEXT,                        -- Comando shell executado (sanitizado)
    execution_output TEXT,                      -- Stdout/stderr do script externo
    rejection_reason TEXT,                      -- Mensagem explicativa em caso de rejeição
    created_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),

    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE RESTRICT,
    FOREIGN KEY (printer_id) REFERENCES printers(id) ON DELETE RESTRICT
);

-- ---------------------------------------------------------------------
-- 5. TABELA: quota_transactions (Auditoria / Extrato de Movimentação)
-- Histórico imutável de todas as movimentações de saldo (débitos e créditos).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS quota_transactions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    print_job_id INTEGER,                       -- Vinculado quando for débito de impressão
    type TEXT NOT NULL CHECK(type IN ('debit', 'credit_grant', 'monthly_reset', 'manual_adjustment', 'refund_failed_job')),
    pages_amount INTEGER NOT NULL CHECK(pages_amount != 0), -- Quantidade debitada ou creditada
    balance_before INTEGER NOT NULL,            -- Saldo disponível antes
    balance_after INTEGER NOT NULL,             -- Saldo disponível após
    description TEXT,                           -- Motivo ou detalhes da movimentação
    created_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),

    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (print_job_id) REFERENCES print_jobs(id) ON DELETE SET NULL
);

-- ---------------------------------------------------------------------
-- ÍNDICES PARA OTIMIZAÇÃO DE CONSULTAS E VALIDAÇÕES RÁPIDAS
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_user_quotas_lookup ON user_quotas(user_id, period_year_month);
CREATE INDEX IF NOT EXISTS idx_print_jobs_user ON print_jobs(user_id, status);
CREATE INDEX IF NOT EXISTS idx_print_jobs_created ON print_jobs(created_at);
CREATE INDEX IF NOT EXISTS idx_quota_transactions_user ON quota_transactions(user_id, created_at);

-- ---------------------------------------------------------------------
-- TRIGGERS: Atualização automática de updated_at
-- ---------------------------------------------------------------------
CREATE TRIGGER IF NOT EXISTS trg_users_updated_at 
AFTER UPDATE ON users
BEGIN
    UPDATE users SET updated_at = datetime('now', 'localtime') WHERE id = OLD.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_printers_updated_at 
AFTER UPDATE ON printers
BEGIN
    UPDATE printers SET updated_at = datetime('now', 'localtime') WHERE id = OLD.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_user_quotas_updated_at 
AFTER UPDATE ON user_quotas
BEGIN
    UPDATE user_quotas SET updated_at = datetime('now', 'localtime') WHERE id = OLD.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_print_jobs_updated_at 
AFTER UPDATE ON print_jobs
BEGIN
    UPDATE print_jobs SET updated_at = datetime('now', 'localtime') WHERE id = OLD.id;
END;

