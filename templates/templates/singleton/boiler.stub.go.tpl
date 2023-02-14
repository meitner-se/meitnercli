// THIS IS A STUB: discard the disclaimer at the top of the file, stubs should be edited.
//
// TODO: Remove ".stub" from the filename and delete the comments above, included the top disclaimer.

var _ repository.Repository = (*repo)(nil)

type repo struct {
    db *sql.DB
    audit audit.Log
}

func New(db *sql.DB, audit audit.Log, logger logger.Log) *repo {
    return &repo{
        db: db,
        audit: audit,
        logger: logger,
    }
}

//go:embed migrations/*.sql
var migrations embed.FS

func (r *repo) Bootstrap() error {
	goose.SetBaseFS(migrations)
	goose.SetTableName("<service>_goose_db_version") // TODO : change table name

	return goose.Up(r.db, "migrations")
}

// WithinTransaction runs a function within a database transaction.
//
// Transaction is propagated in the context, so it is important to propagate it to underlying repositories.
//
// Function commits the transaction if error is nil.
// Function rollbacks the transaction if error is not nil and returns the same error without any wrapping.
func (r *repo) WithinTransaction(ctx context.Context, f func(ctx context.Context) error) error {
    rollbackHandler := func(err error) {
        r.logger.Error(ctx, "failed to rollback transaction", logger.Error(err))
    }

    return database.WithinTransaction(ctx, r.db, rollbackHandler, f)
}
