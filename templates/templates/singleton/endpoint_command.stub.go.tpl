type commandService interface {
{{- range $table := .Tables -}}
    {{- if and (not $table.IsView) (not $table.IsJoinTable) -}}
        {{- $alias := $.Aliases.Table $table.Name -}}
        {{- $colDefs := sqlColDefinitions $table.Columns $table.PKey.Columns -}}
        {{- $pkNames := $colDefs.Names | stringMap (aliasCols $alias) | stringMap $.StringFuncs.camelCase | stringMap $.StringFuncs.replaceReserved -}}
        {{- $pkArgs := joinSlices " " $pkNames $colDefs.Types | join ", " -}}
        
        Create{{ $alias.UpSingular }}(ctx context.Context, {{ $alias.DownSingular }} *model.{{ $alias.UpSingular }}) error
        Update{{ $alias.UpSingular }}(ctx context.Context, {{ $alias.DownSingular }} *model.{{ $alias.UpSingular }}) error
        Delete{{ $alias.UpSingular }}(ctx context.Context, {{ $pkArgs }}) error
    {{ end }}
{{ end }}
}

var _ api.Command_{{getServiceName | titleCase }}Service = (*command)(nil)

type command struct {
    svc commandService
}

func NewCommandEndpoint(svc commandService) *command {
    return &command{
        svc: svc,
    }
}

{{ range $table := .Tables}}
{{- if and (not $table.IsView) (not $table.IsJoinTable) -}}
{{- $alias := $.Aliases.Table $table.Name -}}
{{- $colDefs := sqlColDefinitions $table.Columns $table.PKey.Columns -}}
{{- $pkNames := $colDefs.Names | stringMap (aliasCols $alias) | stringMap $.StringFuncs.titleCase | stringMap $.StringFuncs.replaceReserved -}}

func (c *command) Create{{$alias.UpSingular}}(ctx context.Context, r api.{{$alias.UpSingular}}CreateRequest) (*api.{{$alias.UpSingular}}CreateResponse, error) {
    {{$alias.DownSingular}} := model.{{ $alias.UpSingular }}{
        {{- range $column := $table.Columns -}}
        {{- $colAlias := $alias.Column $column.Name -}}

        {{- if or (eq $column.Name "created_at") (eq $column.Name "updated_at") }}
            {{ $colAlias }}: types.NewTimestampUndefined(), // Undefined since it is an auto-column
        {{- else if or (containsAny $pkNames $colAlias) (eq $column.Name "created_by") (eq $column.Name "updated_by") }}
            {{ $colAlias }}: types.NewUUIDUndefined(), // Undefined since it is an auto-column
        {{- else }}
            {{- if (isEnumDBType .DBType) }}
                {{ $colAlias }}: model.{{ parseEnumName $column.DBType | titleCase }}FromString(r.{{ $colAlias }}),
            {{- else }}
                {{ $colAlias }}: r.{{ $colAlias }},
            {{- end -}}
        {{- end }}
        {{- end }}
        {{ range $rel := getLoadRelations $.Tables $table -}}
        {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
            {{ $relAlias.Local | singular }}IDs: r.{{ $relAlias.Local | singular }}IDs,
        {{end -}}{{- /* range relationships */ -}}
    }

    err := c.svc.Create{{ $alias.UpSingular }}(ctx, &{{$alias.DownSingular}})
    if err != nil {
        return nil, err
    }

    return &api.{{$alias.UpSingular}}CreateResponse{
        ID: {{$alias.DownSingular}}.ID,
    }, nil
}

func (c *command) Update{{$alias.UpSingular}}(ctx context.Context, r api.{{$alias.UpSingular}}UpdateRequest) (*api.{{$alias.UpSingular}}UpdateResponse, error) {
    {{$alias.DownSingular}} := model.{{ $alias.UpSingular }}{
        {{- range $column := $table.Columns -}}
        {{- $colAlias := $alias.Column $column.Name -}}

        {{- if or (eq $column.Name "created_at") (eq $column.Name "updated_at") }}
            {{ $colAlias }}: types.NewTimestampUndefined(), // Undefined since it is an auto-column
        {{- else if or (eq $column.Name "created_by") (eq $column.Name "updated_by") }}
            {{ $colAlias }}: types.NewUUIDUndefined(), // Undefined since it is an auto-column
        {{- else }}
            {{- if (isEnumDBType .DBType) }}
                {{ $colAlias }}: model.{{ parseEnumName $column.DBType | titleCase }}FromString(r.{{ $colAlias }}),
            {{- else }}
                {{ $colAlias }}: r.{{ $colAlias }},
            {{- end -}}
        {{- end }}
        {{- end }}
        {{ range $rel := getLoadRelations $.Tables $table -}}
        {{- $relAlias := $.Aliases.ManyRelationship $rel.ForeignTable $rel.Name $rel.JoinTable $rel.JoinLocalFKeyName -}}
            {{ $relAlias.Local | singular }}IDs: r.{{ $relAlias.Local | singular }}IDs,
        {{end -}}{{- /* range relationships */ -}}
    }

    err := c.svc.Update{{ $alias.UpSingular }}(ctx, &{{$alias.DownSingular}})
    if err != nil {
        return nil, err
    }

    return &api.{{$alias.UpSingular}}UpdateResponse{
        ID: {{$alias.DownSingular}}.ID,
    }, nil
}

func (c *command) Delete{{$alias.UpSingular}}(ctx context.Context, r api.{{$alias.UpSingular}}DeleteRequest) (*api.{{$alias.UpSingular}}DeleteResponse, error) {
    err := c.svc.Delete{{ $alias.UpSingular }}(ctx, {{ prefixStringSlice "r." $pkNames | join ", "}})
    if err != nil {
        return nil, err
    }

    return &api.{{$alias.UpSingular}}DeleteResponse{}, nil
}
{{ end }}
{{ end }}
