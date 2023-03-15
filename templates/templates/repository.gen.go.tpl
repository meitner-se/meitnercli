{{- if .Table.IsView -}}
{{- else -}}
{{- $alias := .Aliases.Table .Table.Name -}}
{{- $colDefs := sqlColDefinitions .Table.Columns .Table.PKey.Columns -}}
{{- $colNames := .Table.Columns | columnNames -}}
{{- $pkNames := $colDefs.Names | stringMap (aliasCols $alias) | stringMap .StringFuncs.camelCase | stringMap .StringFuncs.replaceReserved -}}
{{- $pkArgs := joinSlices " " $pkNames $colDefs.Types | join ", " -}}
{{- $schemaTable := .Table.Name | .SchemaTable}}

type {{$alias.UpSingular}} interface {
    Create{{$alias.UpSingular}}(ctx context.Context, input *model.{{$alias.UpSingular}}) error
    Update{{$alias.UpSingular}}(ctx context.Context, input *model.{{$alias.UpSingular}}) error
    Delete{{$alias.UpSingular}}(ctx context.Context, input *model.{{$alias.UpSingular}}) error
    Get{{$alias.UpSingular}}(ctx context.Context, {{ $pkArgs }}) (*model.{{$alias.UpSingular}}, error)
    Get{{$alias.UpSingular}}WithQueryParams(ctx context.Context, queryParams model.{{$alias.UpSingular}}QueryParams) (*model.{{$alias.UpSingular}}, error)

    {{- range $column := .Table.Columns -}}
        {{- $colAlias := $alias.Column $column.Name -}}
        {{- if and (not (containsAny $.Table.PKey.Columns $column.Name)) ($column.Unique) }}
            Get{{$alias.UpSingular}}By{{$colAlias}}({{if $.NoContext}}{{else}}ctx context.Context,{{end}}{{ camelCase $colAlias }} {{ $column.Type }}) (*model.{{$alias.UpSingular}}, error)
        {{ end }}
    {{end -}}

    List{{$alias.UpPlural}}(ctx context.Context, query model.{{$alias.UpSingular}}Query) ([]*model.{{$alias.UpSingular}}, *types.Int64, error)
    {{ range $fKey := .Table.FKeys -}}
        List{{$alias.UpPlural}}By{{ titleCase $fKey.Column }}({{if $.NoContext}}{{else}}ctx context.Context{{end}}, {{ camelCase $fKey.Column }} types.UUID) ([]*model.{{$alias.UpSingular}}, error)
    {{ end }}
}
{{end -}}
