// THIS IS A STUB: discard the disclaimer at the top of the file, stubs should be edited.
//
// TODO: Remove ".stub" from the filename and delete the comments above, included the top disclaimer.

type repo struct {
    db *sql.DB
    audit audit.Log
}

func New(db *sql.DB) *repo {
    return &repo{
        db: db,
        audit: audit.WriterLog(os.Stdout),
    }
}

//go:embed migrations/*.sql
var migrations embed.FS

func (r *repo) Bootstrap() error {
	goose.SetBaseFS(migrations)
	goose.SetTableName("<service>_goose_db_version") // TODO : change table name

	return goose.Up(r.db, "migrations")
}
