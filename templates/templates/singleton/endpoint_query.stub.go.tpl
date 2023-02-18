type queryService interface {
{{ range $table := .Tables}}
    {{ if and (not $table.IsView) (not $table.IsJoinTable) -}}
        {{- $alias := $.Aliases.Table $table.Name -}}
        {{- $colDefs := sqlColDefinitions $table.Columns $table.PKey.Columns -}}
        {{- $pkNames := $colDefs.Names | stringMap (aliasCols $alias) | stringMap $.StringFuncs.camelCase | stringMap $.StringFuncs.replaceReserved -}}
        {{- $pkArgs := joinSlices " " $pkNames $colDefs.Types | join ", " -}}

        Get{{ $alias.UpSingular }}(ctx context.Context, {{ $pkArgs }}) (*model.{{ $alias.UpSingular }}, error)
        List{{ $alias.UpPlural }}(ctx context.Context, query model.{{ $alias.UpSingular }}Query) ([]*model.{{ $alias.UpSingular }}, *types.Int64, error)

    {{ end }}
{{ end }}
}

type query struct {
    svc queryService
}

func NewQueryEndpoint(svc queryService) *query {
    return &query{
        svc: svc,
    }
}

{{ range $table := .Tables}}
{{ if and (not $table.IsView) (not $table.IsJoinTable) -}}
{{- $alias := $.Aliases.Table $table.Name -}}
{{- $colDefs := sqlColDefinitions $table.Columns $table.PKey.Columns -}}
{{- $pkNames := $colDefs.Names | stringMap (aliasCols $alias) | stringMap $.StringFuncs.titleCase | stringMap $.StringFuncs.replaceReserved -}}

func (q *query) Get{{$alias.UpSingular}}(ctx context.Context, r api.{{$alias.UpSingular}}GetRequest) (*api.{{$alias.UpSingular}}GetResponse, error) {
    {{$alias.DownSingular}}, err := q.svc.Get{{ $alias.UpSingular }}(ctx, {{ prefixStringSlice "r." $pkNames | join ", "}})
    if err != nil {
        return nil, err
    }

    return &api.{{$alias.UpSingular}}GetResponse{
        {{$alias.UpSingular}}: conversion.{{$alias.UpSingular}}FromModel({{$alias.DownSingular}}),
    }, nil
}

func (q *query) List{{$alias.UpPlural}}(ctx context.Context, r api.{{$alias.UpSingular}}ListRequest) (*api.{{$alias.UpSingular}}ListResponse, error) {
    {{$alias.DownPlural}}, {{$alias.DownPlural}}TotalCount, err := q.svc.List{{ $alias.UpPlural }}(ctx, conversion.{{$alias.UpSingular}}QueryToModel(r.Query))
    if err != nil {
        return nil, err
    }

    return &api.{{$alias.UpSingular}}ListResponse{
        {{$alias.UpPlural}}TotalCount: *{{$alias.DownPlural}}TotalCount,
        {{$alias.UpPlural}}: conversion.{{$alias.UpSingular}}FromModels({{$alias.DownPlural}}),
    }, nil
}

{{ end }}
{{ end }}
