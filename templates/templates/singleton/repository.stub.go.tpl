type Repository interface {
{{ range $table := .Tables}}
{{- if not (or ($table.IsView) ($table.IsJoinTable)) -}}
    {{- $alias := $.Aliases.Table $table.Name -}}
    {{ $alias.UpSingular }}
{{ end -}}
{{ end }}

    // WithinTransaction runs a function within a database transaction.
    //
    // Transaction is propagated in the context, so it is important to propagate it to underlying repositories.
    //
    // Function commits the transaction if error is nil.
    // Function rollbacks the transaction if error is not nil and returns the same error without any wrapping.
    WithinTransaction(context.Context, func(ctx context.Context) error) error
}