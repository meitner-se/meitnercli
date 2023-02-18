type svc struct {
    repo repository.Repository
}

func NewService(repo repository.Repository) *svc {
    return &svc{
        repo: repo,
    }
}
