// THIS IS A STUB: discard the disclaimer at the top of the file, stubs should be edited.
//
// TODO: Remove ".stub" from the filename and delete the comments above, included the top disclaimer.

type Repository interface {
    // WithinTransaction runs a function within a database transaction.
    //
    // Transaction is propagated in the context, so it is important to propagate it to underlying repositories.
    //
    // Function commits the transaction if error is nil.
    // Function rollbacks the transaction if error is not nil and returns the same error without any wrapping.
    WithinTransaction(context.Context, func(ctx context.Context) error) error

{{ range $table := .Tables}}
{{- if not $table.IsView -}}
    {{- $alias := $.Aliases.Table $table.Name -}}
    {{ $alias.UpSingular }}
{{ end -}}
{{ end }}
}