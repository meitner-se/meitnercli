const serviceName = "{{ getServiceName }}"

var _ repository.Repository = (*repo)(nil)

type repo struct {
    db *sql.DB
    audit audit.Log
    logger logger.Log
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
	goose.SetTableName(serviceName + "_goose_db_version")

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
        r.logger.Error(ctx, "failed to rollback transaction", 
            logger.Error(err),
            logger.String("service", types.NewString(serviceName)),
        )
    }

    return database.WithinTransaction(ctx, r.db, rollbackHandler, f)
}
