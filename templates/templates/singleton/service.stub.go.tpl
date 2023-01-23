// THIS IS A STUB: discard the disclaimer at the top of the file, stubs should be edited.
//
// TODO: Remove ".stub" from the filename and delete the comments above, included the top disclaimer.

type svc struct {
    repo repository.Repository
}

func NewService(repo repository.Repository) *svc {
    return &svc{
        repo: repo,
    }
}
