// THIS IS A STUB: discard the disclaimer at the top of the file, stubs should be edited.
//
// TODO: Remove ".stub" from the filename and delete the comments above, included the top disclaimer.

type Repository interface {
{{ range $table := .Tables}}
{{- if not $table.IsView -}}
    {{- $alias := $.Aliases.Table $table.Name -}}
    {{ $alias.UpSingular }}
{{ end -}}
{{ end }}
}